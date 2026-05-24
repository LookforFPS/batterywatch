/*
 * read_hid_devices.c — HID battery reader
 *
 * Author: TheDogORB <thedogorb@proton.me>
 */

#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <time.h>
#include <poll.h>
#include <errno.h> 
#include <stdint.h>
#include <stdbool.h>

#define TIMEOUT_SEC     10
#define MAX_DEVICES     8
#define HID_BUFFER_SIZE 64

// Based on QML states
enum ConnectionType {
    CONN_WIRED = 0,
    CONN_WIRELESS = 1,
};

typedef struct {
    uint8_t percentage;
    bool charging;
    enum ConnectionType connection_type;
} DeviceStatus;

/* SC2 related 
 *  28DE:1302 = USB direct
 *  28DE:1303 = Bluetooth >>> HANDLED BY UPOWER MODULE <<<
 *  28DE:1304 = Wireless via puck dongle
 *
 * Valve doesn't expose SC2 (usb/puck) through upower or any other std interface,
 * so it gets read out directly from hidraw
 *
 * Notes from my reverse-engineering:
 *  0x42 - Gamepad controls -> sticks, std buttons
 *  0x43 - see below
 *  0x44 - Haptic motors
 *  0x45 - Trackpads
 *
 * Report 0x43 layout:
 *  byte[0] = 0x43 \\ Report ID
 *  byte[1] = connection state:
 *      - 0x01 = wireless via puck dongle (and bluetooth)
 *      - 0x02 = puck physically connected
 *      - 0x03 = briefly engaged when puck is transitioning from puck to wireless and vice versa
 *      - 0x04 = connected via USB (charging) directly to SC2 or when connected to puck
 *  Still didn't figure out why sometimes 0x04 is enganged instead of 0x02
 *  byte[2] = battery percentage
 */

#define SC2_REPORT_STATUS  0x43
enum SC2ConnState {
    SC2_CONN_INVALID        = 0x00,
    SC2_CONN_WIRELESS       = 0x01,
    SC2_CONN_PUCK           = 0x02,
    SC2_CONN_TRANSITION     = 0x03,
    SC2_CONN_USB            = 0x04,
};

static int parse_sc2(const unsigned char* buf, DeviceStatus* status);

// Generic device abstraction
typedef int (*ParseFn)(const unsigned char* buf, DeviceStatus* status);

typedef struct {
    uint16_t    vid;
    uint16_t    pid;
    int32_t     iface;
    const char* name;
    const char* device_type;
    uint8_t     report_id;
    uint8_t     min_report_len; // e.g. 3 for report ID, battery %, charging state
    ParseFn     parse;
} DeviceDesc;

typedef struct {
    char devpath[64];
    char serial[128];
    const DeviceDesc* desc;
} Device;

// Known devices
static const DeviceDesc known_devices[] = {
    { 0x28DE, 0x1302, 0, "Steam Controller 2", "gamepad", SC2_REPORT_STATUS, 3, parse_sc2 }, // Wired
    { 0x28DE, 0x1304, 2, "Steam Controller 2", "gamepad", SC2_REPORT_STATUS, 3, parse_sc2 }, // Wireless
};

// Goes through /sys/class/hidraw and collects all known interfaces
// Returns the number of devices found
static int find_all_devices(Device* devs, int max) {
    DIR* d = opendir("/sys/class/hidraw");
    if (!d) return 0;

    int count = 0;
    int n_known = sizeof(known_devices) / sizeof(known_devices[0]);
    struct dirent* ent;
    while ((ent = readdir(d)) && count < max) {
        if (ent->d_name[0] == '.') { 
            continue;
        }

        char ue[256];
        snprintf(ue, sizeof(ue), "/sys/class/hidraw/%s/device/uevent", ent->d_name);

        FILE* f = fopen(ue, "r");
        if (!f) { 
            continue;
        }

        char line[1024];
        unsigned int vid = 0, pid = 0;
        int iface = -1;
        char serial[128] = "unknown-hid";

        while (fgets(line, sizeof(line), f)) {
            // VID & PID
            if (strncmp(line, "HID_ID=", 7) == 0) {
                unsigned int bus, v, p;
                if (sscanf(line + 7, "%x:%x:%x", &bus, &v, &p) == 3) {
                    vid = v;
                    pid = p;
                }
            }
            // Interface
            if (strncmp(line, "HID_PHYS=", 9) == 0) {
                char* p = strstr(line, "/input");
                if (p && sscanf(p, "/input%d", &iface) != 1)
                    iface = -1;
            }
            // Serial number
            if (strncmp(line, "HID_UNIQ=", 9) == 0) {
                char* val = line + 9;
                size_t n = strlen(val);
                while (n > 0 && (val[n-1] == '\n' || val[n-1] == '\r')) val[--n] = '\0';
                if (n > 0) snprintf(serial, sizeof(serial), "%s", val);
            }
        }
        fclose(f);

        // Check for known (supported) devices
        const DeviceDesc* matched = NULL;
        for (int k = 0; k < n_known; k++) {
            // Early exit on unknown OEM, hunting down those ns 
            if (vid != known_devices[k].vid) {
                continue;
            }
            if (pid == known_devices[k].pid) {
                // iface < 0 in known_devices means any interface will do
                if (known_devices[k].iface >= 0 && iface != known_devices[k].iface) {
                    continue;
                }
                matched = &known_devices[k];
                break;
            }
        }
        if (matched) {
            snprintf(devs[count].devpath, sizeof(devs[count].devpath), "/dev/%s", ent->d_name);
            snprintf(devs[count].serial, sizeof(devs[count].serial), "%s", serial);
            devs[count].desc = matched;
            count++;
        }
    }
    closedir(d);
    return count;
}

// Parses 0x43 message
// Assumes correct report -> already handled in read_status()
// Returns 1 on OK, 0 on fail; data written in DeviceStatus*
static int parse_sc2(const unsigned char* buf, DeviceStatus* status) {
    uint8_t state = buf[1];

    if (state == SC2_CONN_INVALID || state > SC2_CONN_USB) {
        return 0;
    }

    // It seems that SC2 displays 0x60 (96) as max charge and gets to 0x64 (100) only when a charger is connected
    status->percentage = buf[2] > 100 ? 100 : buf[2];
    status->charging = (state != SC2_CONN_WIRELESS);
    status->connection_type = (state == SC2_CONN_USB) ? CONN_WIRED : CONN_WIRELESS;
    return 1;
}

// Read wrapper
// Returns bytes read; 0 - timeout; -1 - err
static ssize_t read_report(int fd, unsigned char* buf, size_t len, struct timespec deadline) {
    // Poll() struct to save FileDescriptor and Events
    struct pollfd pfd = {
        .fd = fd,
        .events = POLLIN
    };

    // Poll() + EINTR retry loop that keeps firing until timeout is reached or data is available
    while (true) {
        // Calculates time left
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        long ms_left = (deadline.tv_sec - now.tv_sec) * 1000 + (deadline.tv_nsec - now.tv_nsec) / 1000000;
        int timeout = (int)ms_left;

        if (timeout <= 0) {
            return 0;
        }

        // Timeout logic
        int r = poll(&pfd, 1, timeout);
        if (r == 0) {
            return 0;
        }
        if (r > 0) { 
            break;
        }
        if (errno != EINTR) {
            return -1;
        }
    }
    // Error handling
    // POLERR = device err
    // POLLHUP = device disconnected
    // POLLNVAL = invalid FD
    // POLLIN = new data ready
    if (pfd.revents & (POLLERR | POLLHUP | POLLNVAL) ||
        !(pfd.revents & POLLIN)) {
        return -1;
    }
    // Reads out and returns output
    ssize_t n;
    do {
        n = read(fd, buf, len);
    } while (n < 0 && errno == EINTR);

    return n;
}

// Waits for report to arrive or for TIMEOUT_SEC deadline to be reached
// O_NONBLOCK + poll() makes it sleep in kernel with 0 CPU utilisation
// Returns -1 on err, 0 on timeout, and 1 on found
static int read_status(const Device* dev, DeviceStatus* status) {
    int fd = open(dev->devpath, O_RDONLY | O_NONBLOCK);
    if (fd < 0) {
        return -1;
    }

    int ret = 0;
    unsigned char buf[HID_BUFFER_SIZE];
    struct timespec deadline;
    clock_gettime(CLOCK_MONOTONIC, &deadline);
    deadline.tv_sec += TIMEOUT_SEC;

    // Keeps reading report until a valid one is found
    while (true) {
        ssize_t n = read_report(fd, buf, sizeof(buf), deadline);
        if (n == 0) {
            break;
        }
        if (n < 0) {
            ret = -1;
            goto out;
        }
        if (buf[0] != dev->desc->report_id || n < dev->desc->min_report_len) {
            continue;
        }
        if (dev->desc->parse(buf, status)) {
            ret = 1;
            goto out;
        }
    }

    out:
    close(fd);
    return ret;
}

int main(void) {
    Device devs[MAX_DEVICES];
    int count = find_all_devices(devs, MAX_DEVICES);

    // No device connected
    if (count == 0) { 
        puts("[]"); 
        return 0; 
    }

    // JSON output
    printf("[");
    int written = 0;
    for (int i = 0; i < count; i++) {
        DeviceStatus status;
        if (read_status(&devs[i], &status) <= 0) {
            continue;
        }
        if (written > 0) {
            printf(",");
        }
        printf("{\"name\":\"%s\","
                "\"serial\":\"%s\","
                "\"percentage\":%d,"
                "\"charging\":%s,"
                "\"connectionType\":%d,"
                "\"deviceType\":\"%s\"}",
               devs[i].desc->name, devs[i].serial, status.percentage,
               status.charging ? "true" : "false", status.connection_type,
               devs[i].desc->device_type);
        written++;
    }
    printf("]\n");
    return 0;
}
