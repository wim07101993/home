import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// Super+Space. Searches apps and a few actions: updating the system, adding
// and removing web apps, and locking, suspending or leaving the session.
Scope {
    id: root

    property bool open: false
    // "apps" searches apps and actions, "webapp" asks for a web app to add,
    // "remove" lists the web apps to remove.
    property string mode: "apps"
    property string query: ""

    readonly property var actions: [
        { name: "Update system", icon: "system-software-update", detail: "git pull and nixos-rebuild switch", run: () => Terminal.run(["system-update"]) },
        { name: "Install web app", icon: "applications-internet", detail: "A website in a window of its own", keepOpen: true, run: () => root.show("webapp") },
        { name: "Remove web app", icon: "edit-delete", detail: "", keepOpen: true, run: () => root.show("remove") },
        { name: "Lock", icon: "system-lock-screen", detail: "", run: () => Quickshell.execDetached(["loginctl", "lock-session"]) },
        { name: "Suspend", icon: "system-suspend", detail: "", run: () => Quickshell.execDetached(["systemctl", "suspend"]) },
        { name: "Log out", icon: "system-log-out", detail: "", run: () => Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.exit()"]) },
        { name: "Reboot", icon: "system-reboot", detail: "", run: () => Quickshell.execDetached(["systemctl", "reboot"]) },
        { name: "Shut down", icon: "system-shutdown", detail: "", run: () => Quickshell.execDetached(["systemctl", "poweroff"]) },
    ]

    readonly property var results: {
        let items;
        if (mode === "remove") {
            items = DesktopEntries.applications.values
                .filter(entry => entry.id.startsWith("webapp-"))
                .map(entry => ({ name: entry.name, icon: entry.icon, detail: entry.comment, run: () => Quickshell.execDetached(["webapp-remove", entry.id]) }));
        } else {
            items = DesktopEntries.applications.values
                .filter(entry => !entry.noDisplay)
                .map(entry => ({ name: entry.name, icon: entry.icon, detail: entry.genericName || entry.comment, keywords: String(entry.keywords), run: () => launch(entry) }))
                .sort((a, b) => a.name.localeCompare(b.name))
                .concat(actions);
        }

        const q = query.toLowerCase().trim();
        if (q === "")
            return items;
        return items
            .map(item => ({ item: item, rank: rank(item, q) }))
            .filter(ranked => ranked.rank >= 0)
            .sort((a, b) => a.rank - b.rank || a.item.name.localeCompare(b.item.name))
            .map(ranked => ranked.item);
    }

    onOpenChanged: {
        if (open)
            show("apps");
    }
    onResultsChanged: list.currentIndex = 0

    // Lower is better; -1 leaves the item out.
    function rank(item, q) {
        const name = item.name.toLowerCase();
        if (name.startsWith(q))
            return 0;
        if (name.includes(q))
            return 1;
        if (`${item.detail} ${item.keywords ?? ""}`.toLowerCase().includes(q))
            return 2;
        return -1;
    }

    function launch(entry) {
        if (entry.runInTerminal)
            Quickshell.execDetached(["alacritty", "-e", "sh", "-c", entry.execString.replace(/%[a-zA-Z]/g, "")]);
        else
            entry.execute();
    }

    function show(newMode) {
        mode = newMode;
        query = "";
        search.text = "";
        webName.text = "";
        webUrl.text = "";
        webIcon.text = "";
        Qt.callLater(() => (newMode === "webapp" ? webName : search).forceActiveFocus());
    }

    function back() {
        if (mode === "apps")
            open = false;
        else
            show("apps");
    }

    function activate(index) {
        const item = results[index];
        if (!item)
            return;
        item.run();
        if (!item.keepOpen)
            open = false;
    }

    function installWebApp() {
        const name = webName.text.trim();
        const url = webUrl.text.trim();
        if (name === "" || url === "")
            return;
        Quickshell.execDetached(["webapp-install", name, url, webIcon.text.trim()]);
        open = false;
    }

    function iconSource(icon) {
        if (icon && icon.startsWith("/"))
            return "file://" + icon;
        return Quickshell.iconPath(icon || "application-x-executable", "application-x-executable");
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.open = !root.open;
        }
    }

    PanelWindow {
        visible: root.open

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "#66000000"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "launcher"

        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
        }

        Rectangle {
            id: box

            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 5
            width: 640
            height: 460
            color: Theme.background
            border.color: Theme.accent
            border.width: 2

            // Keeps clicks inside the box from closing the launcher.
            MouseArea {
                anchors.fill: parent
            }

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10
                visible: root.mode !== "webapp"

                InputField {
                    id: search

                    width: parent.width
                    placeholder: root.mode === "remove" ? "Remove which web app?" : "Search apps"
                    onTextChanged: root.query = text
                    onAccepted: root.activate(list.currentIndex)
                    Keys.onEscapePressed: root.back()
                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onDownPressed: list.incrementCurrentIndex()
                }

                ListView {
                    id: list

                    width: parent.width
                    height: parent.height - search.height - parent.spacing
                    clip: true
                    model: root.results
                    highlightMoveDuration: 0

                    delegate: Rectangle {
                        id: row

                        required property var modelData
                        required property int index

                        width: list.width
                        height: 44
                        color: ListView.isCurrentItem ? Theme.selection : "transparent"

                        Row {
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12

                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                implicitSize: 28
                                source: root.iconSource(row.modelData.icon)
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    text: row.modelData.name
                                    color: Theme.foreground
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize + 1
                                }

                                Text {
                                    visible: text !== ""
                                    width: list.width - 70
                                    text: row.modelData.detail ?? ""
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 2
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: list.currentIndex = row.index
                            onClicked: root.activate(row.index)
                        }
                    }
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10
                visible: root.mode === "webapp"

                Text {
                    text: "Install web app"
                    color: Theme.foreground
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 2
                    font.bold: true
                }

                InputField {
                    id: webName

                    width: parent.width
                    placeholder: "Name, e.g. WhatsApp"
                    KeyNavigation.tab: webUrl
                    onAccepted: root.installWebApp()
                    Keys.onEscapePressed: root.back()
                }

                InputField {
                    id: webUrl

                    width: parent.width
                    placeholder: "Address, e.g. web.whatsapp.com"
                    KeyNavigation.tab: webIcon
                    onAccepted: root.installWebApp()
                    Keys.onEscapePressed: root.back()
                }

                InputField {
                    id: webIcon

                    width: parent.width
                    placeholder: "Icon address (optional: the site's own icon otherwise)"
                    KeyNavigation.tab: webName
                    onAccepted: root.installWebApp()
                    Keys.onEscapePressed: root.back()
                }

                Text {
                    text: "Tab moves between fields, Enter installs, Esc goes back."
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
            }
        }
    }
}
