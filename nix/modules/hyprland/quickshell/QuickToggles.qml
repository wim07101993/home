import QtQuick

// Stay awake, night light and silence notifications: lit while on.
Row {
    spacing: 14

    BarButton {
        // coffee, coffee-off
        text: String.fromCodePoint(Toggles.stayAwake ? 0xF0176 : 0xF06CA)
        color: Toggles.stayAwake ? Theme.accent : Theme.dim
        onClicked: Toggles.stayAwake = !Toggles.stayAwake
    }

    BarButton {
        // weather-night
        text: String.fromCodePoint(0xF0594)
        color: Toggles.nightLight ? Theme.accent : Theme.dim
        onClicked: Toggles.nightLight = !Toggles.nightLight
    }

    BarButton {
        // bell-off, bell
        text: String.fromCodePoint(Toggles.silent ? 0xF009B : 0xF009A)
        color: Toggles.silent ? Theme.accent : Theme.dim
        onClicked: Toggles.silent = !Toggles.silent
    }
}
