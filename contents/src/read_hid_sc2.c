/*
 * read_hid_sc2.c — Steam Controller 2 (Valve 28DE:1304 wireless / 28DE:1302 USB) battery reader
 *
 * Valve doesn't expose SC2 through upower or any other std interface, 
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
 *      - 0x01 = wireless via puck dongle
 *      - 0x02 = puck physically connected
 *      - 0x03 = briefly engaged when puck is transitioning from puck to wireless and vice versa
 *      - 0x04 = connected via USB (charging) directly to SC2 or when connected to puck
 *  Still didn't figure out why sometimes 0x04 is enganged instead of 0x02
 *  byte[2] = battery percentage
 *  byte[3+] = might be bluetooth info? To be tested in the near future
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

#define TIMEOUT_SEC 6
#define MAX_DEVICES 8

typedef struct {
    char devpath[64];
    char serial[64];
} SC2Dev;

// Goes through /sys/class/hidraw and collects all SC2 interfaces
// Wireless (via puck): VID 28DE + PID 1304 + "input2" in HID_PHYS
// TODO: ?Bluetooth?:   VID 28DE + PID ??? + "input?" in HID_HYS
// Direct USB:          VID 28DE + PID 1302 + "input0" in HID_PHYS
// Returns the number of devices found
static int find_all_sc2(SC2Dev* devs, int max) {
    DIR* d = opendir("/sys/class/hidraw");
    if (!d) return 0;

    int count = 0;
    struct dirent* ent;
    while ((ent = readdir(d)) && count < max) {
        if (ent->d_name[0] == '.') continue;

        char ue[256];
        snprintf(ue, sizeof(ue), "/sys/class/hidraw/%s/device/uevent", ent->d_name);

        FILE* f = fopen(ue, "r");
        if (!f) continue;

        char line[256];
        int vid = 0, pid = 0, iface = -1;
        char serial[64] = "sc2-hid";

        // PID 0x1302 + interface 0 = USB to controller, wired connection
        // TODO: Check if 0x1303 + interface 1 == bluetooth or not
        // PID 0x1304 + interface 2 = puck
        while (fgets(line, sizeof(line), f)) {
            if (strstr(line, "000028DE")) {
                vid = 1;
            }
            if (strstr(line, "00001302")) {
                pid = 0x1302;
            }
            if (strstr(line, "00001304")) {
                pid = 0x1304;
            }
            if (strstr(line, "HID_PHYS") && strstr(line, "input0")) {
                 iface = 0;
            }
            if (strstr(line, "HID_PHYS") && strstr(line, "input2")) { 
                iface = 2;
            }
            // Serial number
            if (strncmp(line, "HID_UNIQ=", 9) == 0) {
                char* val = line + 9;
                size_t n = strlen(val);
                while (n > 0 && (val[n-1] == '\n' || val[n-1] == '\r')) {
                    val[--n] = '\0';
                }
                if (n > 0) {
                    snprintf(serial, sizeof(serial), "%s", val);
                }
            }
        }
        fclose(f);

        int match = vid && ((pid == 0x1304 && iface == 2) || (pid == 0x1302 && iface == 0));
        if (match) {
            snprintf(devs[count].devpath, sizeof(devs[count].devpath), "/dev/%s", ent->d_name);
            snprintf(devs[count].serial, sizeof(devs[count].serial), "%s", serial);
            count++;
        }
    }
    closedir(d);
    return count;
}

// Parses 0x43 message
static int parse_0x43(unsigned char* buf, int* percentage, int* charging, int* connectionType) {
    if (buf[0] != 0x43) {
        return 0;
    }
    if (buf[1] == 0x00 || buf[1] > 0x04) {
        return 0;
    }

    // It seems that SC2 displays 0x60 as max charge and gets to 0x64 only when a charger is connected
    *percentage = buf[2] > 100 ? 100 : buf[2];
    *charging = (buf[1] != 0x01);
    *connectionType = (buf[1] == 0x04) ? 0 : 1;
    return 1;
}

// Waits for 0x43 report to arrive or for TIMEOUT_SEC deadline to be reached
// O_NONBLOCK + poll() makes it sleep in kernel with 0 CPU utilisation
static int read_status(const char* devpath, int* percentage, int* charging, int* connectionType) {
    int fd = open(devpath, O_RDONLY | O_NONBLOCK);
    if (fd < 0) return 0;

    unsigned char buf[64];
    struct pollfd pfd = { .fd = fd, .events = POLLIN };
    time_t deadline = time(NULL) + TIMEOUT_SEC;
    int found = 0;

    while (1) {
        // Recompute remaining time
        int ms_left = (int)(deadline - time(NULL)) * 1000;
        if (ms_left <= 0 || poll(&pfd, 1, ms_left) <= 0) break;

        ssize_t n = read(fd, buf, sizeof(buf));
        // 0x43 needs at least 3 bytes: report ID, connection state, battery percentage
        if (n < 3) {
            continue;
        }
        if (parse_0x43(buf, percentage, charging, connectionType)) {
            found = 1;
            break;
        }
    }

    close(fd);
    return found;
}

int main(void) {
    SC2Dev devs[MAX_DEVICES];
    int count = find_all_sc2(devs, MAX_DEVICES);

    // No device connected
    if (count == 0) { 
        puts("[]"); 
        return 0; 
    }

    // JSON output
    printf("[");
    int written = 0;
    for (int i = 0; i < count; i++) {
        int percentage, charging, connectionType;
        if (!read_status(devs[i].devpath, &percentage, &charging, &connectionType)) {
             continue;
        }
        if (written > 0) { 
            printf(",");
        }
        printf("{\"name\":\"Steam Controller 2\","
                "\"serial\":\"%s\","
                "\"percentage\":%d,"
                "\"charging\":%s,"
                "\"connectionType\":%d,"
                "\"deviceType\":\"gamepad\","
                "\"bluetoothAddress\":null}",
               devs[i].serial, percentage, charging ? "true" : "false", connectionType);
        written++;
    }
    printf("]\n");
    // Exit after printing JSON
    return 0;
}
