/*
 * gpio_session.h -- GpioSession: RAII pigpio lifecycle with DMA crash recovery
 *
 * Factory create() handles the full startup sequence:
 *   1. Recover any leaked DMA handles from prior crash
 *   2. Probe baseline handles
 *   3. gpioInitialise()
 *   4. Probe again, diff to find our handles
 *   5. Save our handles to state file
 *
 * Destructor calls gpioTerminate() and clears the state file.
 * Move-only (no copy).
 */

#pragma once

#include <algorithm>
#include <cstdio>
#include <optional>
#include <string_view>
#include <utility>
#include <vector>

#include <pigpio.h>
#include "dma_guard.h"
#include "gpio_pigpio.h"

class GpioSession {
public:
    static std::optional<GpioSession> create(
        std::string_view state_path = "/run/treadmill-io.dma-handles")
    {
        DmaGuard dma(state_path);

        // Step 1: recover leaked handles from prior crash
        int recovered = dma.recover_leaked();
        if (recovered > 0) {
            std::fprintf(stderr, "GpioSession: recovered %d leaked DMA handles\n",
                         recovered);
        } else if (recovered < 0) {
            std::fprintf(stderr, "GpioSession: warning: corrupt state file (deleted)\n");
        }

        // Step 2: probe baseline handles
        auto baseline = dma.probe_allocated();

        // Step 3: initialise pigpio
        if (gpioInitialise() < 0) {
            std::fprintf(stderr, "GpioSession: gpioInitialise() failed\n");
            return std::nullopt;
        }

        // Step 4: probe again, compute diff (our handles = after - baseline)
        auto after = dma.probe_allocated();

        std::vector<uint32_t> ours;
        for (auto h : after) {
            // If h is not in baseline, it's ours
            bool in_baseline = false;
            for (auto b : baseline) {
                if (b == h) { in_baseline = true; break; }
            }
            if (!in_baseline) ours.push_back(h);
        }

        std::fprintf(stderr, "GpioSession: pigpio allocated %zu DMA handles\n",
                     ours.size());

        // Step 5: save our handles to state file
        dma.save(ours);

        return GpioSession(std::move(dma));
    }

    ~GpioSession() {
        if (alive_) {
            gpioTerminate();
            dma_.clear();
            alive_ = false;
        }
    }

    GpioSession(GpioSession&& o) noexcept
        : dma_(std::move(o.dma_))
        , port_(o.port_)
        , alive_(o.alive_)
    {
        o.alive_ = false;
    }

    GpioSession& operator=(GpioSession&& o) noexcept {
        if (this != &o) {
            if (alive_) {
                gpioTerminate();
                dma_.clear();
            }
            dma_ = std::move(o.dma_);
            port_ = o.port_;
            alive_ = o.alive_;
            o.alive_ = false;
        }
        return *this;
    }

    GpioSession(const GpioSession&) = delete;
    GpioSession& operator=(const GpioSession&) = delete;

    PigpioPort& port() { return port_; }

private:
    explicit GpioSession(DmaGuard dma)
        : dma_(std::move(dma)) {}

    DmaGuard dma_;
    PigpioPort port_;
    bool alive_ = true;
};
