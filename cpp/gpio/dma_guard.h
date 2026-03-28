/*
 * dma_guard.h -- DmaGuard: GPU mailbox handle manager for crash recovery
 *
 * The VideoCore GPU allocates DMA memory handles via /dev/vcio. pigpio
 * acquires these on gpioInitialise() but they leak on abnormal exit
 * (SIGKILL, segfault) because the GPU firmware has no concept of Linux
 * process death. This class tracks and recovers leaked handles.
 *
 * No knowledge of pigpio -- only mailbox ioctl protocol and state files.
 */

#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

class DmaGuard {
public:
    explicit DmaGuard(std::string_view state_path = "/run/treadmill-io.dma-handles");
    ~DmaGuard();  // closes /dev/vcio fd if open

    DmaGuard(DmaGuard&& o) noexcept;
    DmaGuard& operator=(DmaGuard&& o) noexcept;
    DmaGuard(const DmaGuard&) = delete;
    DmaGuard& operator=(const DmaGuard&) = delete;

    // Recover leaked handles from prior crash (reads + deletes state file).
    // Returns number of handles freed, or -1 on parse error.
    int recover_leaked();

    // Probe which handles are currently allocated (non-destructive lock/unlock).
    // Empirically, pigpio on RPi 4 allocates ~23 handles in range 0xf0-0x110.
    // 1024 provides generous headroom. Probing takes ~5ms for 1024 handles.
    static constexpr uint32_t DEFAULT_MAX_HANDLE = 1024;
    std::vector<uint32_t> probe_allocated(uint32_t max_handle = DEFAULT_MAX_HANDLE);

    // Free specific handles
    void free_handles(const std::vector<uint32_t>& handles);

    // Persist handle list to state file (hex format, one per line)
    bool save(const std::vector<uint32_t>& handles);

    // Delete state file
    void clear();

private:
    std::string state_path_;
    int vcio_fd_ = -1;

    bool open_vcio();
    std::vector<uint32_t> read_state_file();

    // Mailbox primitives
    bool mbox_lock(uint32_t handle);    // returns true if handle exists
    void mbox_unlock(uint32_t handle);
    bool mbox_free(uint32_t handle);    // returns true if freed successfully
};
