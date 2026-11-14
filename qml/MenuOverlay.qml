// Keuzemenu over het hele scherm, te bedienen met pijltjes/Enter/Esc en gamepad.
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick

FocusScope {
    id: overlay

    property string title
    property string message           // optionele uitleg onder de titel
    property var entries: []          // [{ label: "...", action: "..." }]
    property Item returnFocusTo: null
    signal chosen(string action)

    anchors.fill: parent
    visible: false
    z: 100

    function open(menuTitle, menuEntries, focusItem, menuMessage) {
        title = menuTitle
        message = menuMessage || ""
        entries = menuEntries
        returnFocusTo = focusItem
        list.currentIndex = 0
        visible = true
        list.forceActiveFocus()
    }

    function close() {
        visible = false
        if (returnFocusTo) {
            returnFocusTo.forceActiveFocus()
        }
    }

    function choose(index) {
        const action = entries[index].action
        close()
        chosen(action)
    }

    Rectangle {
        anchors.fill: parent
        color: "#b0000000"
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true; onClicked: overlay.close() }
    }

    Rectangle {
        id: panel
        readonly property real unit: overlay.height / 100
        anchors.centerIn: parent
        width: Math.min(overlay.width * 0.8, unit * 70)
        height: titleLabel.height + (messageLabel.visible ? messageLabel.height + unit * 1.5 : 0) + list.height + unit * 9
        radius: unit * 2
        color: "#1d2a40"
        border.color: "#44ffffff"
        border.width: 1
        MouseArea { anchors.fill: parent }

        Text {
            id: titleLabel
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: panel.unit * 3
            color: "white"
            font.pixelSize: (panel.unit * 3.4) * appModel.fontScale
            elide: Text.ElideRight
            text: overlay.title
        }
        Text {
            id: messageLabel
            visible: overlay.message !== ""
            anchors.top: titleLabel.bottom
            anchors.topMargin: panel.unit * 1.5
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: panel.unit * 3
            anchors.rightMargin: panel.unit * 3
            color: "#d5d8dc"
            font.pixelSize: panel.unit * 2.5 * appModel.fontScale
            wrapMode: Text.Wrap
            text: overlay.message
        }

        ListView {
            id: list
            anchors.top: messageLabel.visible ? messageLabel.bottom : titleLabel.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: panel.unit * 3
            height: count * panel.unit * 8
            model: overlay.entries
            focus: true
            interactive: false
            keyNavigationEnabled: true

            delegate: Rectangle {
                id: row
                required property int index
                required property var modelData
                width: list.width
                height: panel.unit * 8
                radius: panel.unit * 1.2
                color: list.currentIndex === index ? "#3d6fb4" : "transparent"

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: panel.unit * 2.5
                    color: "white"
                    font.pixelSize: (panel.unit * 2.8) * appModel.fontScale
                    text: row.modelData.label
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: list.currentIndex = row.index
                    onClicked: overlay.choose(row.index)
                }
            }

            Keys.onReturnPressed: overlay.choose(currentIndex)
            Keys.onEnterPressed: overlay.choose(currentIndex)
            Keys.onEscapePressed: overlay.close()
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Menu || event.key === Qt.Key_Back) {
                    overlay.close()
                    event.accepted = true
                }
            }
        }
    }
}
