// Bench firmware for the "IO8 Pulse Bench Rig" (a bare ESP32-S3 dev board plus
// the Rev E charge pump on a breadboard). It answers questions an emulator
// cannot: how long a flash erase stops the RELAY_PULSE edges on real silicon
// with the radio running, and how far the Q3 gate node sags when it does.
//
// It is NOT the product firmware. The pulse permission below is a C port of
// safety_core::liveness::PulseBudget with the same constants, kept small on
// purpose; the Rust original is the one that ships and is the one tested.
//
// Wiring: GPIO8 -> pump input, GPIO4 (ADC1 channel 3) <- gate node, 3V3, GND.
#include <inttypes.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>

#include "driver/gpio.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "esp_partition.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"

#define PIN_PULSE GPIO_NUM_8
#define GATE_ADC_CHANNEL ADC_CHANNEL_3 // GPIO4 on ADC1

#define HALF_PERIOD_US 500
#define PERMIT_US 20000
#define PERMIT_EDGES (PERMIT_US / HALF_PERIOD_US + 4)
#define LOOP_PERIOD_MS 5
#define ERASE_PERIOD_MS 3000
#define REPORT_PERIOD_MS 5000
#define SECTOR 4096
#define Q3_THRESHOLD_MAX_MV 1450

// Pulse permission (see the header comment).
static atomic_bool s_armed;
static atomic_uint s_expiry_us, s_edges_left, s_last_tick_us;
static bool s_level;

// Measurements. Written by one task each, read by the reporter.
static atomic_uint s_tick_gap_max_us, s_tick_gap_max_ever_us, s_tick_late_count, s_edges;
static atomic_uint s_loop_gap_max_us, s_loop_gap_max_ever_us;
static atomic_int s_gate_now_mv, s_gate_min_mv, s_gate_min_ever_mv;
static atomic_uint s_erase_count, s_erase_last_us, s_erase_max_us;
static atomic_int s_gate_after_stall_last_mv, s_gate_after_stall_min_mv;
static atomic_uint s_stall_last_us, s_stall_max_us;

static adc_oneshot_unit_handle_t s_adc;
static adc_cali_handle_t s_cali;

static uint32_t now_us(void) { return (uint32_t)esp_timer_get_time(); }

static void bump_max(atomic_uint *slot, uint32_t value) {
    uint32_t seen = atomic_load(slot);
    while (value > seen && !atomic_compare_exchange_weak(slot, &seen, value)) {
    }
}
static void bump_min(atomic_int *slot, int value) {
    int seen = atomic_load(slot);
    while (value < seen && !atomic_compare_exchange_weak(slot, &seen, value)) {
    }
}

static void on_tick(void *arg) {
    uint32_t now = now_us();
    uint32_t gap = now - atomic_exchange(&s_last_tick_us, now);
    bump_max(&s_tick_gap_max_us, gap);
    bump_max(&s_tick_gap_max_ever_us, gap);
    if (gap > 2000) atomic_fetch_add(&s_tick_late_count, 1);

    bool armed = atomic_load(&s_armed) && gap <= PERMIT_US;
    uint32_t remaining = atomic_load(&s_expiry_us) - now;
    bool live = armed && remaining != 0 && remaining <= PERMIT_US;
    if (live) {
        uint32_t left = atomic_load(&s_edges_left);
        live = left > 0 && atomic_compare_exchange_strong(&s_edges_left, &left, left - 1);
    }
    if (!live) atomic_store(&s_armed, false);
    s_level = live && !s_level;
    gpio_set_level(PIN_PULSE, s_level);
    if (live) atomic_fetch_add(&s_edges, 1);
}

static void renew(void) {
    atomic_store(&s_expiry_us, now_us() + PERMIT_US);
    atomic_store(&s_edges_left, PERMIT_EDGES);
    atomic_store(&s_armed, true);
}

static int read_gate_mv(void) {
    int raw = 0, mv = 0;
    if (adc_oneshot_read(s_adc, GATE_ADC_CHANNEL, &raw) != ESP_OK) return -1;
    if (s_cali && adc_cali_raw_to_voltage(s_cali, raw, &mv) == ESP_OK) return mv;
    return raw * 3100 / 4095; // uncalibrated estimate at 12 dB attenuation
}

// Stands in for the 5 ms serial engine: renews the permission and watches the gate.
static void loop_task(void *arg) {
    TickType_t wake = xTaskGetTickCount();
    uint32_t last = now_us();
    for (;;) {
        uint32_t now = now_us();
        uint32_t gap = now - last;
        last = now;
        // Read the gate BEFORE renewing: after a stall this is its lowest
        // point, because it only recovers once pulses resume.
        int mv = read_gate_mv();
        renew();
        bump_max(&s_loop_gap_max_us, gap);
        bump_max(&s_loop_gap_max_ever_us, gap);
        if (mv >= 0) {
            atomic_store(&s_gate_now_mv, mv);
            bump_min(&s_gate_min_mv, mv);
            if (now > 2000000) bump_min(&s_gate_min_ever_mv, mv);
            if (gap > 10000) { // this task was held off: a stall just ended
                atomic_store(&s_stall_last_us, gap);
                bump_max(&s_stall_max_us, gap);
                atomic_store(&s_gate_after_stall_last_mv, mv);
                bump_min(&s_gate_after_stall_min_mv, mv);
            }
        }
        vTaskDelayUntil(&wake, pdMS_TO_TICKS(LOOP_PERIOD_MS));
    }
}

// Does what a workout checkpoint does: erase a 4 KB sector, then program it.
static void flash_task(void *arg) {
    const esp_partition_t *part = esp_partition_find_first(ESP_PARTITION_TYPE_DATA, 0x40, "bench");
    if (!part) {
        printf("BENCH no 'bench' partition: flash stalls will not be exercised\n");
        vTaskDelete(NULL);
    }
    static uint8_t page[SECTOR];
    uint32_t sector = 0, sectors = part->size / SECTOR;
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(ERASE_PERIOD_MS));
        memset(page, (int)(sector * 37 + 5), sizeof page); // programmed cells make the next erase do real work
        int64_t t0 = esp_timer_get_time();
        esp_err_t err = esp_partition_erase_range(part, sector * SECTOR, SECTOR);
        uint32_t erase_us = (uint32_t)(esp_timer_get_time() - t0);
        if (err == ESP_OK) err = esp_partition_write(part, sector * SECTOR, page, sizeof page);
        if (err != ESP_OK) printf("BENCH flash error %s\n", esp_err_to_name(err));
        atomic_store(&s_erase_last_us, erase_us);
        bump_max(&s_erase_max_us, erase_us);
        atomic_fetch_add(&s_erase_count, 1);
        sector = (sector + 1) % sectors;
    }
}

static void start_radio(void) {
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_ap();
    wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&init));
    wifi_config_t ap = {.ap = {.ssid = "pulse-bench", .ssid_len = 11, .channel = 6, .max_connection = 2, .authmode = WIFI_AUTH_OPEN}};
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_AP));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &ap));
    ESP_ERROR_CHECK(esp_wifi_start());
}

void app_main(void) {
    gpio_set_direction(PIN_PULSE, GPIO_MODE_OUTPUT);
    gpio_set_level(PIN_PULSE, 0);

    adc_oneshot_unit_init_cfg_t unit = {.unit_id = ADC_UNIT_1};
    ESP_ERROR_CHECK(adc_oneshot_new_unit(&unit, &s_adc));
    adc_oneshot_chan_cfg_t chan = {.atten = ADC_ATTEN_DB_12, .bitwidth = ADC_BITWIDTH_DEFAULT};
    ESP_ERROR_CHECK(adc_oneshot_config_channel(s_adc, GATE_ADC_CHANNEL, &chan));
    adc_cali_curve_fitting_config_t cali = {.unit_id = ADC_UNIT_1, .chan = GATE_ADC_CHANNEL, .atten = ADC_ATTEN_DB_12, .bitwidth = ADC_BITWIDTH_DEFAULT};
    if (adc_cali_create_scheme_curve_fitting(&cali, &s_cali) != ESP_OK) s_cali = NULL;

    atomic_store(&s_gate_min_mv, 9999);
    atomic_store(&s_gate_min_ever_mv, 9999);
    atomic_store(&s_gate_after_stall_min_mv, 9999);

    vTaskDelay(pdMS_TO_TICKS(1500)); // let the gate node discharge from any earlier run
    printf("\nBENCH pulse bench: GPIO8 -> pump, GPIO4 <- gate. ADC %s.\n", s_cali ? "calibrated" : "UNCALIBRATED");
    printf("BENCH gate at rest: %d mV (expect about 0)\n", read_gate_mv());

    const esp_timer_create_args_t args = {.callback = on_tick, .name = "relay_pulse", .skip_unhandled_events = true};
    esp_timer_handle_t timer;
    ESP_ERROR_CHECK(esp_timer_create(&args, &timer));
    atomic_store(&s_last_tick_us, now_us());
    ESP_ERROR_CHECK(esp_timer_start_periodic(timer, HALF_PERIOD_US));

    // Charge from cold, radio off, sampling every millisecond.
    int64_t t0 = esp_timer_get_time();
    int reached_ms = -1, at30 = 0;
    for (int ms = 1; ms <= 200; ms++) {
        renew();
        vTaskDelay(pdMS_TO_TICKS(1));
        int mv = read_gate_mv();
        if (reached_ms < 0 && mv >= Q3_THRESHOLD_MAX_MV) reached_ms = (int)((esp_timer_get_time() - t0) / 1000);
        if (ms == 30) at30 = mv;
    }
    printf("BENCH charge from cold: reached %d mV after %d ms (-1 = never); %d mV at 30 ms; %d mV at 200 ms\n",
           Q3_THRESHOLD_MAX_MV, reached_ms, at30, read_gate_mv());

    xTaskCreatePinnedToCore(loop_task, "loop", 4096, NULL, 10, NULL, 0);
    vTaskDelay(pdMS_TO_TICKS(3000));
    printf("BENCH radio off, no flash writes: gate %d mV, worst tick gap %" PRIu32 " us\n", atomic_load(&s_gate_now_mv),
           (uint32_t)atomic_load(&s_tick_gap_max_ever_us));

    start_radio();
    xTaskCreatePinnedToCore(flash_task, "flash", 8192, NULL, 2, NULL, 0);
    printf("BENCH Wi-Fi AP 'pulse-bench' on; erasing one 4 KB sector every %d ms\n", ERASE_PERIOD_MS);

    for (uint32_t t = REPORT_PERIOD_MS / 1000;; t += REPORT_PERIOD_MS / 1000) {
        vTaskDelay(pdMS_TO_TICKS(REPORT_PERIOD_MS));
        printf("BENCH t=%" PRIu32 "s gate_mv now=%d min5s=%d min=%d | tick_gap_us max5s=%u max=%u late=%u | loop_gap_us max5s=%u max=%u"
               " | erase n=%u last_ms=%u.%u max_ms=%u.%u | stall last_ms=%u.%u max_ms=%u.%u gate_after_mv last=%d min=%d\n",
               t, atomic_load(&s_gate_now_mv), atomic_exchange(&s_gate_min_mv, 9999), atomic_load(&s_gate_min_ever_mv),
               atomic_exchange(&s_tick_gap_max_us, 0), atomic_load(&s_tick_gap_max_ever_us), atomic_load(&s_tick_late_count),
               atomic_exchange(&s_loop_gap_max_us, 0), atomic_load(&s_loop_gap_max_ever_us), atomic_load(&s_erase_count),
               atomic_load(&s_erase_last_us) / 1000, atomic_load(&s_erase_last_us) % 1000 / 100, atomic_load(&s_erase_max_us) / 1000,
               atomic_load(&s_erase_max_us) % 1000 / 100, atomic_load(&s_stall_last_us) / 1000, atomic_load(&s_stall_last_us) % 1000 / 100,
               atomic_load(&s_stall_max_us) / 1000, atomic_load(&s_stall_max_us) % 1000 / 100,
               atomic_load(&s_gate_after_stall_last_mv), atomic_load(&s_gate_after_stall_min_mv));
    }
}
