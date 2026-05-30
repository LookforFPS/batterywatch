import QtQuick 2.15
import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.plasma.plasmoid 2.0
import "../DeviceUtils.js" as DeviceUtils

// Razer device provider
// Based on UPowerProvider.qml
// Author: TheDogORB <thedogorb@proton.me>

Item {
    id: root
    visible: false

    // Helper getDevices var
    readonly property string getDeviceListCmd: "qdbus org.razer /org/razer razer.devices.getDevices"

    // Can't test this as I don't have means to connect mouse to PC via Bluetooth
    // but based on what I found on the openrazer github, Bluetooth is currently
    // unsupported, and devices connected via this mean are handled by kernel/OS
    // https://github.com/openrazer/openrazer/issues?q=state%3Aopen%20label%3ABluetooth

    // 0 = wired; 1 = wireless (dongle); 2 = bluetooth
    readonly property int wirelessType: 1

    // Data passed to the applet
    property var devices: []

    property var deviceData: ({})
    property var knownDevices: ({})
    readonly property var emptyList: []

    property bool razerEnabled: Plasmoid.configuration.enableOpenRazerIntegration

    onRazerEnabledChanged: {
        if (!razerEnabled) {
            devices = [];
            deviceData = {};
            knownDevices = {};
        } else {
            refresh();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GUI RELATED FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    // Refresh via "refresh" button in the GUI
    function refresh() {
        listSource.disconnectSource(getDeviceListCmd);
        listSource.connectSource(getDeviceListCmd);

        for (let id in deviceData) {
            fetchPowerInfo(id);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    // Updates the device model from the current internal state
    function updateOpenRazerDevices() {
        let result = [];

        for (let id in deviceData) {
            let d = deviceData[id];

            // Filter out devices w/o a battery or disconnected devices
            //
            // When device gets DCed but its dongle is still connected, name,
            // type vars still persists but battery charge (and firmware version)
            // is set to 0 (and v0.0 respectively) when device is powered off
            //
            // openrazer can report battery being 100% charged up to 30s after
            // connecting a device
            if (typeof d.battery !== "number") {
                continue;
            }
            if (d.firmware === undefined || d.firmware === "v0.0") {
                continue;
            }
            result.push({
                name: d.name || i18n("Unknown Razer Device"),
                serial: id,
                percentage: d.battery,
                charging: d.charging === true,
                type: d.type || "unknown",
                icon: DeviceUtils.getIconForType(d.type || "unknown"),
                connectionType: wirelessType,   // Always wireless, openRazer doesn't support Bluetooth devices -> handled by kernel
                source: "openrazer",
                batteries: emptyList           // OpenRazer does not support multiple batteries, only razer.device.power.getBattery() is exposed
            });
        }

        // Sorts devices alphabetically, name is always d.name or Unknown Razer Device
        result.sort((a, b) => a.name.localeCompare(b.name));

        // Skips UI redraw if nothing has changed
        if (result.length === devices.length) {
            let changed = false;
            for (let i = 0; i < result.length; i++) {
                const r = result[i], d = devices[i];
                if (
                    r.serial !== d.serial || 
                    r.percentage !== d.percentage ||
                    r.charging !== d.charging || 
                    r.name !== d.name
                    ) {
                    changed = true;
                    break;
                }
            }
            if (!changed)
                return;
        }

        devices = result;
    }

    function fetchNameAndType(id) {
        detailsSource.connectSource(`qdbus org.razer /org/razer/device/${id} razer.device.misc.getDeviceName`);
        detailsSource.connectSource(`qdbus org.razer /org/razer/device/${id} razer.device.misc.getDeviceType`);
    }

    function fetchPowerInfo(id) {
        if (!deviceData[id])
            return;
        batterySource.connectSource(`qdbus org.razer /org/razer/device/${id} razer.device.power.getBattery`);
        chargingSource.connectSource(`qdbus org.razer /org/razer/device/${id} razer.device.power.isCharging`);
        detailsSource.connectSource(`qdbus org.razer /org/razer/device/${id} razer.device.misc.getFirmware`);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEVICE DISCOVERY
    // ═══════════════════════════════════════════════════════════════════════

    // openrazer lacks device added/removed signal -> instead devices are polled
    // periodically razer.devices.getDevices function
    // Result is then diffed against list of devices known in the last run of the
    // function -> new/disconnected devices are found
    P5Support.DataSource {
        id: listSource
        engine: "executable"
        interval: 0

        onNewData: (src, data) => {
            disconnectSource(src);

            const ids = data.stdout.split("\n").map(s => s.trim()).filter(Boolean);

            let current = {};

            ids.forEach(id => {
                current[id] = true;

                if (!root.knownDevices[id]) {
                    root.deviceData[id] = {
                        name: "",
                        type: "",
                        firmware: undefined,
                        battery: undefined,
                        charging: false
                    };

                    root.fetchNameAndType(id);
                    root.fetchPowerInfo(id);
                }
            });

            // Remove unresponsive/stale devices
            for (let id in root.knownDevices) {
                if (!current[id]) {
                    delete root.deviceData[id];
                }
            }

            root.knownDevices = current;
            Qt.callLater(root.updateOpenRazerDevices);
        }

        Component.onCompleted: {
            if (root.razerEnabled)
                connectSource(root.getDeviceListCmd);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BATTERY HANDLING
    // ═══════════════════════════════════════════════════════════════════════

    // Updates percentage (battery charge) values via razer.device.power.getBattery
    // if the func exists for a device -> func doesn't exist for wired devices
    P5Support.DataSource {
        id: batterySource
        engine: "executable"
        interval: 0

        onNewData: (src, data) => {
            disconnectSource(src);

            if (!src.includes("/device/"))
                return;
            const id = src.split("/device/")[1].split(" ")[0];
            if (!root.deviceData[id])
                return;

            // Non-battery device
            if (data.stderr && data.stderr.includes("UnknownMethod")) {
                delete root.deviceData[id];
                Qt.callLater(root.updateOpenRazerDevices);
                return;
            }

            // 0 is handled in updateOpenRazerDevices()
            const raw = parseFloat(data.stdout);
            if (isNaN(raw))
                return;
            root.deviceData[id].battery = Math.round(Math.max(0, Math.min(100, raw)));

            Qt.callLater(root.updateOpenRazerDevices);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CHARGING HANDLING
    // ═══════════════════════════════════════════════════════════════════════

    // Updates isCharging to true/false via razer.device.power.isCharging
    P5Support.DataSource {
        id: chargingSource
        engine: "executable"
        interval: 0

        onNewData: (src, data) => {
            disconnectSource(src);

            if (!src.includes("/device/"))
                return;
            const id = src.split("/device/")[1].split(" ")[0];
            if (!root.deviceData[id])
                return;

            if (data.stderr && data.stderr.length > 0)
                return;
            root.deviceData[id].charging = data.stdout.trim() === "true";

            Qt.callLater(root.updateOpenRazerDevices);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // META DATA
    // ═══════════════════════════════════════════════════════════════════════

    P5Support.DataSource {
        id: detailsSource
        engine: "executable"
        interval: 0

        onNewData: (src, data) => {
            disconnectSource(src);

            if (!src.includes("/device/"))
                return;
            const id = src.split("/device/")[1].split(" ")[0];
            if (!root.deviceData[id]) {
                return;
            }
            // name/type fetched once on connect
            // ignore errors to avoid overwriting with empty/garbage values
            if (data.stderr && data.stderr.length > 0) {
                return;
            }
            if (src.endsWith("getDeviceName")) {
                root.deviceData[id].name = data.stdout.trim();
            } else if (src.endsWith("getDeviceType")) {
                root.deviceData[id].type = data.stdout.trim();
            } else if (src.endsWith("getFirmware")) {
                root.deviceData[id].firmware = data.stdout.trim();
            }

            Qt.callLater(root.updateOpenRazerDevices);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TIMERS
    // ═══════════════════════════════════════════════════════════════════════

    // Periodic 'device discovery' scan + battery refresh
    Timer {
        interval: Plasmoid.configuration.openRazerPollingTime * 1000
        running: root.razerEnabled
        repeat: true
        onTriggered: root.refresh()
    }
}
