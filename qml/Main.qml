// Placeholder voor de echte shell-UI (containments/homescreen uit de
// Linux-broncode kan hier later ingehangen worden als QML-module).
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick

Rectangle {
    id: root
    color: "#1b2a41"
    focus: true

    Keys.onEscapePressed: Qt.quit()

    Column {
        anchors.centerIn: parent
        spacing: 24

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: "white"
            font.pixelSize: Math.max(32, root.height / 12)
            text: "Bigscreen Host"
        }
        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#9fd3ff"
            font.pixelSize: Math.max(24, root.height / 8)
            text: Qt.formatTime(new Date(), "HH:mm:ss")
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#cccccc"
            font.pixelSize: Math.max(16, root.height / 30)
            text: "Windows PoC -- druk op Esc om af te sluiten"
        }
    }

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: clock.text = Qt.formatTime(new Date(), "HH:mm:ss")
    }
}
