import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

// Tray icons, then Bluetooth, network, volume, power profile and battery.
// A click opens the matching terminal UI; see each icon for its other buttons.
Row {
    id: root

    required property var bar

    spacing: 14

    Tray {
        anchors.verticalCenter: parent.verticalCenter
        bar: root.bar
    }

    // Right click switches Bluetooth on or off.
    BarButton {
        id: bluetooth

        readonly property var adapter: Bluetooth.defaultAdapter
        readonly property bool connected: adapter ? adapter.devices.values.some(d => d.connected) : false

        visible: adapter !== null
        // bluetooth-off, bluetooth-connect, bluetooth
        text: String.fromCodePoint(!adapter?.enabled ? 0xF00B2 : connected ? 0xF00B1 : 0xF00AF)
        color: adapter?.enabled ? Theme.foreground : Theme.dim
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                adapter.enabled = !adapter.enabled;
            else
                Terminal.run(["bluetui"]);
        }
    }

    BarButton {
        readonly property bool wired: Networking.devices.values.some(d => d.type === DeviceType.Wired && d.connected)
        readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi && d.connected) ?? null
        readonly property var network: wifi?.networks.values.find(n => n.connected) ?? null
        readonly property real strength: network ? network.signalStrength : 0

        // ethernet, wifi-strength-off, wifi-strength-outline to wifi-strength-4
        text: String.fromCodePoint(wired ? 0xF0200 : !network ? 0xF092E : [0xF092F, 0xF091F, 0xF0922, 0xF0925, 0xF0928][Math.min(4, Math.floor(strength * 5))])
        color: wired || network ? Theme.foreground : Theme.dim
        onClicked: Terminal.run(["nmtui"])
    }

    // Right click mutes, the wheel changes the volume.
    BarButton {
        readonly property var sink: Pipewire.defaultAudioSink
        readonly property real volume: sink?.audio?.volume ?? 0
        readonly property bool muted: sink?.audio?.muted ?? true

        // volume-mute, volume-low, volume-medium, volume-high
        text: String.fromCodePoint(muted ? 0xF075F : volume < 0.34 ? 0xF057F : volume < 0.67 ? 0xF0580 : 0xF057E)
        color: muted ? Theme.dim : Theme.foreground
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                sink.audio.muted = !muted;
            else
                Terminal.run(["wiremix"]);
        }
        onScrolled: delta => {
            if (sink?.audio)
                sink.audio.volume = Math.max(0, Math.min(1, volume + (delta > 0 ? 0.05 : -0.05)));
        }

        PwObjectTracker {
            objects: [Pipewire.defaultAudioSink]
        }
    }

    // A click moves to the next power profile.
    BarButton {
        readonly property var profiles: PowerProfiles.hasPerformanceProfile
            ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
            : [PowerProfile.PowerSaver, PowerProfile.Balanced]

        // leaf, scale-balance, rocket-launch
        text: String.fromCodePoint(PowerProfiles.profile === PowerProfile.PowerSaver ? 0xF032A : PowerProfiles.profile === PowerProfile.Performance ? 0xF14DE : 0xF05D1)
        onClicked: PowerProfiles.profile = profiles[(profiles.indexOf(PowerProfiles.profile) + 1) % profiles.length]
    }

    Text {
        readonly property var battery: UPower.displayDevice
        readonly property real level: battery.energyCapacity > 0 ? battery.energy / battery.energyCapacity : 0
        readonly property bool charging: battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged

        visible: battery.isLaptopBattery
        // battery-charging, battery-10 to battery-90, battery
        text: String.fromCodePoint(charging ? 0xF0084 : [0xF007A, 0xF007B, 0xF007C, 0xF007D, 0xF007E, 0xF007F, 0xF0080, 0xF0081, 0xF0082, 0xF0079][Math.max(0, Math.min(9, Math.ceil(level * 10) - 1))]) + " " + Math.round(level * 100) + "%"
        color: level < 0.15 && !charging ? Theme.red : Theme.foreground
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
    }
}
