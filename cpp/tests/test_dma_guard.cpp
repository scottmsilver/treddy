/*
 * test_dma_guard.cpp -- Unit tests for DmaGuard state file logic
 *
 * Tests file I/O only (save/read_state_file/clear/recover_leaked).
 * Does NOT require /dev/vcio -- runs anywhere.
 */

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#define DOCTEST_CONFIG_NO_EXCEPTIONS
#include <doctest.h>

#include "gpio/dma_guard.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <unistd.h>

// Helper: create a unique temp file path and return it.
// The file is created then immediately closed (so the path is valid).
static std::string make_temp_path() {
    char tmpl[] = "/tmp/test_dma_guard_XXXXXX";
    int fd = ::mkstemp(tmpl);
    if (fd >= 0) ::close(fd);
    // Remove the file so DmaGuard starts clean
    ::unlink(tmpl);
    return std::string(tmpl);
}

// ── State file round-trip ────────────────────────────────────────────

TEST_CASE("state file round-trip") {
    auto path = make_temp_path();
    DmaGuard guard(path);

    std::vector<uint32_t> handles = {0xf6, 0xf7, 0xf8};
    CHECK(guard.save(handles));

    // Verify file exists
    CHECK(::access(path.c_str(), F_OK) == 0);

    // Read back via recover_leaked (which reads + frees + deletes).
    // Since we don't have /dev/vcio, free_handles will fail silently
    // on each handle (ioctl fails), but the count should be correct.
    // Instead, verify the file content directly.
    FILE* f = std::fopen(path.c_str(), "r");
    CHECK(f != nullptr);

    char line[64];
    std::vector<uint32_t> read_back;
    while (std::fgets(line, sizeof(line), f)) {
        if (line[0] == '\n' || line[0] == '\0') continue;
        char* end = nullptr;
        unsigned long val = std::strtoul(line, &end, 16);
        read_back.push_back(static_cast<uint32_t>(val));
    }
    std::fclose(f);

    CHECK(read_back.size() == handles.size());
    CHECK(read_back.at(0) == 0xf6);
    CHECK(read_back.at(1) == 0xf7);
    CHECK(read_back.at(2) == 0xf8);

    // Cleanup
    ::unlink(path.c_str());
}

// ── Clear deletes file ───────────────────────────────────────────────

TEST_CASE("clear deletes state file") {
    auto path = make_temp_path();
    DmaGuard guard(path);

    guard.save({0x10, 0x20});
    CHECK(::access(path.c_str(), F_OK) == 0);

    guard.clear();
    CHECK(::access(path.c_str(), F_OK) != 0);
}

// ── Recover with no file returns 0 ──────────────────────────────────

TEST_CASE("recover with no file returns 0") {
    auto path = make_temp_path();
    DmaGuard guard(path);

    // No state file exists
    int result = guard.recover_leaked();
    CHECK(result == 0);
}

// ── Recover with file frees and deletes ──────────────────────────────

TEST_CASE("recover with file frees and deletes") {
    auto path = make_temp_path();

    // Write a state file manually
    FILE* f = std::fopen(path.c_str(), "w");
    CHECK(f != nullptr);
    std::fprintf(f, "f6\nf7\nf8\n");
    std::fclose(f);

    DmaGuard guard(path);
    int result = guard.recover_leaked();

    // Should report 3 handles (even though free fails without /dev/vcio,
    // recover_leaked returns the count from the file)
    CHECK(result == 3);

    // State file should be deleted
    CHECK(::access(path.c_str(), F_OK) != 0);
}

// ── Empty handle list ────────────────────────────────────────────────

TEST_CASE("empty handle list") {
    auto path = make_temp_path();
    DmaGuard guard(path);

    // Save empty list
    guard.save({});

    // File should exist (even if empty)
    CHECK(::access(path.c_str(), F_OK) == 0);

    // Recover should return 0 (nothing to free)
    int result = guard.recover_leaked();
    CHECK(result == 0);

    // File should be deleted
    CHECK(::access(path.c_str(), F_OK) != 0);
}

// ── Corrupt state file returns -1 ───────────────────────────────────

TEST_CASE("corrupt state file returns -1") {
    auto path = make_temp_path();

    // Write garbage
    FILE* f = std::fopen(path.c_str(), "w");
    CHECK(f != nullptr);
    std::fprintf(f, "not_hex_at_all\n");
    std::fclose(f);

    DmaGuard guard(path);
    int result = guard.recover_leaked();
    CHECK(result == -1);

    // File should be deleted even on error
    CHECK(::access(path.c_str(), F_OK) != 0);
}
