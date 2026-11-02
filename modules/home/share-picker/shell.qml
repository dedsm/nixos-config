// The screen share picker: a button on every visible window and monitor, as on
// macOS. It prints nothing itself: share-picker.sh hands the choice to xdph, in
// the same format as hyprland-share-picker. See docs/share-picker.md.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: root

    readonly property var monitors: JSON.parse(Quickshell.env("PICKER_MONITORS") || "[]")
    readonly property var clients: JSON.parse(Quickshell.env("PICKER_CLIENTS") || "[]")
    readonly property bool allowToken: Quickshell.env("PICKER_ALLOW_TOKEN") === "1"
    readonly property var entries: parseEntries(Quickshell.env("XDPH_WINDOW_SHARING_LIST") || "")
    readonly property var shareable: joinClients()
    readonly property var hiddenWindows: shareable.filter(w => !w.visible)

    // xdph's list: id[HC>]class[HT>]title[HE>]address[HA>], repeated.
    function parseEntries(list) {
        return list.split("[HA>]").filter(item => item.length > 0).map(item => {
            const [id, rest] = item.split("[HC>]");
            const [windowClass, rest2] = rest.split("[HT>]");
            const [title, address] = rest2.split("[HE>]");
            return { id, windowClass, title, address: Number(address) };
        });
    }

    function joinClients() {
        const result = [];
        for (const entry of entries) {
            const client = clients.find(c => parseInt(c.address, 16) === entry.address)
                || clients.find(c => c.class === entry.windowClass && c.title === entry.title);
            const monitor = client ? monitors.find(m => m.id === client.monitor) : null;
            const visible = !!client && !!monitor && client.mapped && !client.hidden
                && client.workspace.id === monitor.activeWorkspace.id;
            result.push({ id: entry.id, windowClass: entry.windowClass, title: entry.title, visible,
                          monitor: monitor ? monitor.name : "", client });
        }
        // Painted in order, so what's on top on screen is on top here.
        return result.sort((a, b) => rank(a) - rank(b));
    }

    function rank(w) {
        if (!w.client) return 0;
        const layer = w.client.fullscreen ? 2000 : (w.client.floating ? 1000 : 0);
        return layer + (100 - w.client.focusHistoryID);
    }

    function label(w) {
        return w.title || w.windowClass;
    }

    function choose(target) {
        writer.command = ["sh", "-c", 'printf "%s" "$1" > "$PICKER_OUT"', "sh",
                          "[SELECTION]" + (allowToken ? "r" : "") + "/" + target];
        writer.running = true;
    }

    function cancel() {
        writer.command = ["sh", "-c", 'printf "CANCEL" > "$PICKER_OUT"'];
        writer.running = true;
    }

    Process {
        id: writer
        onExited: Qt.quit()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData
            readonly property var monitor: root.monitors.find(m => m.name === modelData.name) || null

            screen: modelData
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "share-picker"
            // On demand, not exclusive, which would keep the pointer on one
            // screen. Hyprland focuses it on map, so Escape still works.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.cancel()

                Rectangle {
                    anchors.fill: parent
                    color: "#99000000"
                }

                Repeater {
                    model: root.shareable.filter(w => w.visible && w.monitor === panel.modelData.name)

                    Rectangle {
                        id: frame
                        required property var modelData
                        x: modelData.client.at[0] - panel.monitor.x
                        y: modelData.client.at[1] - panel.monitor.y
                        width: modelData.client.size[0]
                        height: modelData.client.size[1]
                        radius: 12
                        color: area.containsMouse ? "#334f8cff" : "#14ffffff"
                        border.width: area.containsMouse ? 3 : 1
                        border.color: area.containsMouse ? "#4f8cff" : "#66ffffff"

                        MouseArea {
                            id: area
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.choose("window:" + frame.modelData.id)
                        }

                        PickerButton {
                            anchors.centerIn: parent
                            text: "Share This Window"
                            detail: root.label(frame.modelData)
                            hot: area.containsMouse
                            maxWidth: frame.width - 32
                            onClicked: root.choose("window:" + frame.modelData.id)
                        }
                    }
                }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 48
                    spacing: 12

                    PickerButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Share Entire Screen"
                        detail: panel.modelData.name
                        onClicked: root.choose("screen:" + panel.modelData.name)
                    }

                    PickerButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: panel.monitor && panel.monitor.focused
                        quiet: true
                        text: "Cancel (Esc)"
                        onClicked: root.cancel()
                    }
                }

                // Windows on other workspaces have nothing to put a button on.
                Rectangle {
                    visible: panel.monitor && panel.monitor.focused && root.hiddenWindows.length > 0
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 48
                    width: 360
                    height: Math.min(list.contentHeight + 56, parent.height / 2)
                    radius: 12
                    color: "#ee1c1c20"

                    Text {
                        id: heading
                        x: 16
                        y: 14
                        text: "Other windows"
                        color: "#aaffffff"
                        font.pixelSize: 13
                    }

                    ListView {
                        id: list
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; top: heading.bottom; margins: 8 }
                        clip: true
                        model: root.hiddenWindows
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            width: ListView.view.width
                            height: 36
                            radius: 8
                            color: rowArea.containsMouse ? "#4f8cff" : "transparent"
                            Text {
                                anchors.fill: parent
                                anchors.margins: 8
                                text: root.label(row.modelData)
                                color: "white"
                                font.pixelSize: 14
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }
                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.choose("window:" + row.modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
