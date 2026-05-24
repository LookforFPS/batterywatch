import QtQuick 2.15
import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.plasma.plasmoid 2.0
import "../DeviceUtils.js" as DeviceUtils

// Steam Controller 2 (Valve 28DE:1304 wireless / 28DE:1302 USB) battery provider
// Based on OpenRazerProvider.qml
// Author: TheDogORB <thedogorb@proton.me>
//
// The SC2 doesn't support upower, hence the battery info is read out directly via hidraw.
// To read out the controller info, a small C helper is used (read_hid_devices, compiled from read_hid_devices.c during build/install).
// Requires access to /dev/hidraw*; should be granted by default via Steam udev rules.
//
// Notes:
// 0x42 - Controls -> D-pad, sticks, paddles, buttons etc.
// 0x43 - Charging state | Charge 
// 0x44 - Haptics
// 0x45 - Trackpads 

Item {
    id: root
    visible: false

    // Helper binary, reads out hidraw, returns JSON with data
    readonly property string helperPath: Qt.resolvedUrl("../../bin/read_hid_devices").toString().slice(7)

    // Connection types
    readonly property int wirelessType: 1

    // Data passed to the applet
    property var devices: []

    // Holds the last parsed data while waiting for new ones
    property var pendingData: null
    readonly property var emptyList: []

    // UI enabler
    property bool scEnabled: Plasmoid.configuration.enableSteamControllerIntegration

    onScEnabledChanged: {
        if (!scEnabled) {
            devices = []
            pendingData = null
            retryTimer.stop()
        } else {
            refresh()
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GUI RELATED FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    // Refresh via "refresh" button in the GUI
    function refresh() {
        pollSource.disconnectSource(helperPath)
        pollSource.connectSource(helperPath)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    // Rebuilds the devices list from pendingData and updates the applet
    // Happens only if something actually changed -> skips unnecessary UI redraws
    function updateDevices() {
        const parsed = root.pendingData
        if (!parsed) return

        // Parses data, number check is redundand but better to be safe than sorry
        const result = parsed
            .filter(d => typeof d.percentage === "number")
            .map(d => ({
                name: d.name || i18n("Unknown Device"),
                serial: d.serial || d.name,
                percentage: d.percentage,
                charging: d.charging === true,
                type: d.deviceType,
                icon: DeviceUtils.getIconForType(d.deviceType),
                connectionType: (typeof d.connectionType === "number") ? d.connectionType : wirelessType,
                source: "hid-sc2",
                batteries: emptyList,
            }))

        if (result.length === devices.length) {
            const oldMap = {}
            for (const d of devices)
                oldMap[d.serial] = d

            const changed = result.some(n => {
                const o = oldMap[n.serial]
                return !o || o.percentage !== n.percentage || o.charging !== n.charging
            })
            if (!changed) return
        }

        devices = result
    }

    // ═══════════════════════════════════════════════════════════════════════
    // POLLING
    // ═══════════════════════════════════════════════════════════════════════

    // Refreshes on report every ~3-5s
    // When the controller is disconnected, timer is used instead to check for new SC2 devices
    P5Support.DataSource {
        id: pollSource
        engine: "executable"
        connectedSources: []
        interval: 0

        onNewData: (src, data) => {
            disconnectSource(src)

            if (!root.scEnabled) {
                root.devices = []
                return
            }

            if (!data.stdout || data["exit code"] !== 0) {
                if (root.devices.length > 0)
                    root.devices = []
                retryTimer.restart()
                return
            }

            try {
                const parsed = JSON.parse(data.stdout.trim())
                if (!Array.isArray(parsed) || parsed.length === 0) {
                    if (root.devices.length > 0)
                        root.devices = []
                    retryTimer.restart()
                    return
                }
                root.pendingData = parsed
                Qt.callLater(root.updateDevices)
                // Reschedules immiedately, hidraw gets updated every ~3-5s
                Qt.callLater(root.refresh)
            } catch (e) {
                console.warn("BatteryWatch SC2: Failed to parse helper output:", e)
                root.devices = []
                retryTimer.restart()
            }
        }

        Component.onCompleted: {
            if (root.scEnabled)
                root.refresh()
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TIMERS
    // ═══════════════════════════════════════════════════════════════════════

    // Polling timer, used only when the controller is missing as it updates on signal refresh otherwise
    // Signal is received every ~3-5s
    // Watcher using inotify would be less demanding but would required dependency
    Timer {
        id: retryTimer
        interval: Plasmoid.configuration.steamControllerPollingTime * 1000
        repeat: false
        onTriggered: root.refresh()
    }
}