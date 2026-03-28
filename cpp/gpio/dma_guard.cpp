/*
 * dma_guard.cpp -- DmaGuard implementation: mailbox ioctl + state file I/O
 *
 * Uses the VideoCore mailbox interface (/dev/vcio) to probe, lock, unlock,
 * and free GPU DMA memory handles. State file persists handle numbers across
 * crashes so the next startup can reclaim them.
 */

#include "dma_guard.h"

#include <array>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>

// ioctl constant for /dev/vcio on aarch64:
// _IOC(READ|WRITE, 0x64, 0, 8) = (3 << 30) | (8 << 16) | (0x64 << 8) | 0
static constexpr unsigned long IOCTL_MBOX_PROPERTY =
    (3UL << 30) | (8UL << 16) | (0x64UL << 8) | 0;

// Mailbox property tags
static constexpr uint32_t TAG_LOCK_MEMORY    = 0x3000d;
static constexpr uint32_t TAG_UNLOCK_MEMORY  = 0x3000e;
static constexpr uint32_t TAG_RELEASE_MEMORY = 0x3000f;

// Response code indicating success
static constexpr uint32_t RESPONSE_SUCCESS = 0x80000000;

DmaGuard::DmaGuard(std::string_view state_path)
    : state_path_(state_path) {}

DmaGuard::~DmaGuard() {
    if (vcio_fd_ >= 0) {
        ::close(vcio_fd_);
        vcio_fd_ = -1;
    }
}

DmaGuard::DmaGuard(DmaGuard&& o) noexcept
    : state_path_(std::move(o.state_path_))
    , vcio_fd_(o.vcio_fd_)
{
    o.vcio_fd_ = -1;
}

DmaGuard& DmaGuard::operator=(DmaGuard&& o) noexcept {
    if (this != &o) {
        if (vcio_fd_ >= 0) ::close(vcio_fd_);
        state_path_ = std::move(o.state_path_);
        vcio_fd_ = o.vcio_fd_;
        o.vcio_fd_ = -1;
    }
    return *this;
}

bool DmaGuard::open_vcio() {
    if (vcio_fd_ >= 0) return true;
    vcio_fd_ = ::open("/dev/vcio", O_RDWR);
    if (vcio_fd_ < 0) {
        std::fprintf(stderr, "DmaGuard: failed to open /dev/vcio: %s\n",
                     std::strerror(errno));
        return false;
    }
    return true;
}

// Property buffer format (7 uint32_t words):
//   [0] total_size (28 bytes)
//   [1] request_code (0 = request)
//   [2] tag
//   [3] value_buf_size (4 bytes)
//   [4] request_indicator (0)
//   [5] value (handle in, result out)
//   [6] end_tag (0)

bool DmaGuard::mbox_lock(uint32_t handle) {
    if (!open_vcio()) return false;

    std::array<uint32_t, 7> buf = {
        7 * 4,           // total size
        0,               // request code
        TAG_LOCK_MEMORY, // tag
        4,               // value buffer size
        0,               // request indicator
        handle,          // input: handle
        0                // end tag
    };

    if (::ioctl(vcio_fd_, IOCTL_MBOX_PROPERTY, buf.data()) < 0)
        return false;

    // Success: response code has bit 31 set AND bus address is non-zero
    return (buf.at(1) == RESPONSE_SUCCESS) && (buf.at(5) != 0);
}

void DmaGuard::mbox_unlock(uint32_t handle) {
    if (!open_vcio()) return;

    std::array<uint32_t, 7> buf = {
        7 * 4,             // total size
        0,                 // request code
        TAG_UNLOCK_MEMORY, // tag
        4,                 // value buffer size
        0,                 // request indicator
        handle,            // input: handle
        0                  // end tag
    };

    ::ioctl(vcio_fd_, IOCTL_MBOX_PROPERTY, buf.data());
}

bool DmaGuard::mbox_free(uint32_t handle) {
    if (!open_vcio()) return false;

    std::array<uint32_t, 7> buf = {
        7 * 4,              // total size
        0,                  // request code
        TAG_RELEASE_MEMORY, // tag
        4,                  // value buffer size
        0,                  // request indicator
        handle,             // input: handle
        0                   // end tag
    };

    if (::ioctl(vcio_fd_, IOCTL_MBOX_PROPERTY, buf.data()) < 0)
        return false;

    // Success: response code has bit 31 set AND status is 0
    return (buf.at(1) == RESPONSE_SUCCESS) && (buf.at(5) == 0);
}

std::vector<uint32_t> DmaGuard::probe_allocated(uint32_t max_handle) {
    std::vector<uint32_t> allocated;

    for (uint32_t h = 0; h < max_handle; ++h) {
        if (mbox_lock(h)) {
            allocated.push_back(h);
            mbox_unlock(h);
        }
    }

    return allocated;
}

void DmaGuard::free_handles(const std::vector<uint32_t>& handles) {
    for (auto h : handles) {
        if (mbox_free(h)) {
            std::fprintf(stderr, "DmaGuard: freed handle 0x%x\n", h);
        } else {
            std::fprintf(stderr, "DmaGuard: failed to free handle 0x%x\n", h);
        }
    }
}

bool DmaGuard::save(const std::vector<uint32_t>& handles) {
    FILE* f = std::fopen(state_path_.c_str(), "w");
    if (!f) {
        std::fprintf(stderr, "DmaGuard: failed to write %s: %s\n",
                     state_path_.c_str(), std::strerror(errno));
        return false;
    }

    for (auto h : handles) {
        std::fprintf(f, "%x\n", h);
    }

    std::fclose(f);
    return true;
}

void DmaGuard::clear() {
    ::unlink(state_path_.c_str());
}

std::vector<uint32_t> DmaGuard::read_state_file() {
    std::vector<uint32_t> handles;

    FILE* f = std::fopen(state_path_.c_str(), "r");
    if (!f) return handles;

    char line[64];
    while (std::fgets(line, sizeof(line), f)) {
        // Skip empty lines
        if (line[0] == '\n' || line[0] == '\0') continue;

        char* end = nullptr;
        unsigned long val = std::strtoul(line, &end, 16);
        if (end == line) {
            // Parse error: not a valid hex number
            std::fclose(f);
            handles.clear();
            // Signal parse error by returning empty + setting errno-like flag
            // Caller (recover_leaked) distinguishes "no file" from "corrupt file"
            // by checking file existence separately. We use a sentinel approach:
            // push UINT32_MAX to signal corruption.
            handles.push_back(UINT32_MAX);
            return handles;
        }
        handles.push_back(static_cast<uint32_t>(val));
    }

    std::fclose(f);
    return handles;
}

int DmaGuard::recover_leaked() {
    // Check if state file exists
    if (::access(state_path_.c_str(), F_OK) != 0)
        return 0;  // no file, nothing to recover

    auto handles = read_state_file();

    // Check for parse error sentinel
    if (handles.size() == 1 && handles.at(0) == UINT32_MAX) {
        std::fprintf(stderr, "DmaGuard: corrupt state file %s, deleting\n",
                     state_path_.c_str());
        clear();
        return -1;
    }

    if (handles.empty()) {
        // File existed but was empty — nothing to free
        clear();
        return 0;
    }

    std::fprintf(stderr, "DmaGuard: recovering %zu leaked handles from %s\n",
                 handles.size(), state_path_.c_str());

    free_handles(handles);
    clear();

    return static_cast<int>(handles.size());
}
