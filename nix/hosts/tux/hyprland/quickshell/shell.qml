//@ pragma UseQApplication
// UseQApplication: tray icons open their menus as platform (QMenu) menus.

import QtQuick
import Quickshell

ShellRoot {
    Variants {
        model: Quickshell.screens

        delegate: Component {
            Bar {
                required property var modelData
                screen: modelData
            }
        }
    }

    Launcher {}
    Notifications {}
}
