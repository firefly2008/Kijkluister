// Opnemen van live tv: map kiezen, duur kiezen, lopende opname volgen en
// eerdere opnames terugkijken. Het opnemen zelf doet ffmpeg (zie recorder.cpp).
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Dialogs

FocusScope {
    id: panel

    property real unit: height / 100
    property var channel: ({})
    property Item returnFocusTo: null
    property int confirmDelete: -1
    readonly property var durations: [0, 30, 60, 90, 120, 180]
    property int durationIndex: 2

    anchors.fill: parent
    visible: false
    z: 45

    function open(ch, focusItem) {
        channel = ch || {}
        returnFocusTo = focusItem
        confirmDelete = -1
        message.text = ""
        if (recorder.folder === "") {
            recorder.folder = recorder.defaultFolder()
        }
        recorder.refresh()
        visible = true
        if (recorder.recording) {
            stopButton.forceActiveFocus()
        } else {
            startButton.forceActiveFocus()
        }
    }

    function close() {
        visible = false
        if (returnFocusTo) {
            returnFocusTo.forceActiveFocus()
        }
    }

    function fmtTime(s) {
        if (s < 0) return ""
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60
        return (h > 0 ? h + ":" : "") + (m < 10 && h > 0 ? "0" : "") + m + ":" + (sec < 10 ? "0" : "") + sec
    }
    function fmtSize(b) {
        return b > 1e9 ? (b / 1e9).toFixed(2) + " GB" : b > 1e6 ? Math.round(b / 1e6) + " MB" : Math.round(b / 1e3) + " kB"
    }

    function startRecording() {
        if (!channel.url) {
            message.text = "Geen zender gekozen"
            return
        }
        if (recorder.start(channel.name, channel.url, durations[durationIndex])) {
            message.text = ""
            stopButton.forceActiveFocus()
        } else {
            message.text = recorder.status
        }
    }

    FolderDialog {
        id: folderDialog
        title: "Map voor opnames kiezen"
        onAccepted: recorder.folder = recorder.localPath(selectedFolder)
    }

    Keys.onEscapePressed: close()
    Keys.onBackPressed: close()
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_R) {
            close()
            event.accepted = true
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#e60b0c0f"
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }
    }

    Column {
        id: content
        x: panel.unit * 6
        y: panel.unit * 5
        width: parent.width - panel.unit * 12
        spacing: panel.unit * 1.6

        Text {
            color: "white"
            font.pixelSize: panel.unit * 4
            font.weight: Font.DemiBold
            text: "Opnemen  ·  " + (panel.channel.name || "")
        }
        Text {
            color: "#80848b"
            font.pixelSize: panel.unit * 2
            text: "Esc / B / R sluiten    ·    de opname loopt door op de achtergrond, ook als je een andere zender kijkt"
        }

        // Map
        Text { color: "#9fb4d0"; font.pixelSize: panel.unit * 2.2; text: "Opslaan in" }
        Row {
            spacing: panel.unit * 1.5
            Rectangle {
                width: content.width - folderButton.width - openButton.width - panel.unit * 3
                height: panel.unit * 6
                radius: panel.unit
                color: "#0f1115"
                border.width: 1
                border.color: "#33ffffff"
                Text {
                    anchors.fill: parent
                    anchors.margins: panel.unit * 1.5
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideMiddle
                    color: "white"
                    font.pixelSize: panel.unit * 2.3
                    text: recorder.folder
                }
            }
            FocusButton {
                id: folderButton
                unit: panel.unit
                text: "Andere map…"
                enabled: !recorder.recording
                onClicked: folderDialog.open()
                KeyNavigation.right: openButton
                KeyNavigation.down: durationRow
            }
            FocusButton {
                id: openButton
                unit: panel.unit
                text: "Map openen"
                onClicked: recorder.openFolder()
                KeyNavigation.left: folderButton
                KeyNavigation.down: durationRow
            }
        }

        // Duur
        Text { color: "#9fb4d0"; font.pixelSize: panel.unit * 2.2; text: "Duur" }
        FocusScope {
            id: durationRow
            width: content.width
            height: panel.unit * 6
            property int current: panel.durationIndex
            onActiveFocusChanged: if (activeFocus) durationButtons.itemAt(panel.durationIndex).forceActiveFocus()
            KeyNavigation.up: folderButton
            KeyNavigation.down: recorder.recording ? stopButton : startButton
            Row {
                spacing: panel.unit * 1.2
                Repeater {
                    id: durationButtons
                    model: panel.durations
                    delegate: FocusButton {
                        required property int modelData
                        required property int index
                        unit: panel.unit
                        text: modelData === 0 ? "Tot ik stop" : (modelData >= 60 ? (modelData / 60) + " uur" : modelData + " min")
                        checked: index === panel.durationIndex
                        enabled: !recorder.recording
                        onClicked: panel.durationIndex = index
                        KeyNavigation.left: index > 0 ? durationButtons.itemAt(index - 1) : null
                        KeyNavigation.right: index < panel.durations.length - 1 ? durationButtons.itemAt(index + 1) : null
                        KeyNavigation.up: folderButton
                        KeyNavigation.down: recorder.recording ? stopButton : startButton
                    }
                }
            }
        }

        // Start / stop + voortgang
        Row {
            spacing: panel.unit * 2
            FocusButton {
                id: startButton
                unit: panel.unit
                text: "●  Opname starten"
                visible: !recorder.recording
                onClicked: panel.startRecording()
                KeyNavigation.up: durationRow
                KeyNavigation.down: list
            }
            FocusButton {
                id: stopButton
                unit: panel.unit
                text: "■  Opname stoppen"
                visible: recorder.recording
                onClicked: recorder.stop()
                KeyNavigation.up: durationRow
                KeyNavigation.down: list
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.unit * 0.4
                Row {
                    spacing: panel.unit
                    Rectangle {
                        visible: recorder.recording
                        anchors.verticalCenter: parent.verticalCenter
                        width: panel.unit * 1.8; height: width; radius: width / 2
                        color: "#e53935"
                        SequentialAnimation on opacity {
                            running: recorder.recording; loops: Animation.Infinite
                            NumberAnimation { to: 0.2; duration: 600 } NumberAnimation { to: 1; duration: 600 }
                        }
                    }
                    Text {
                        color: "white"
                        font.pixelSize: panel.unit * 2.6
                        text: recorder.recording
                              ? recorder.channel + "   " + panel.fmtTime(recorder.elapsedSeconds)
                                + (recorder.remainingSeconds >= 0 ? "   (nog " + panel.fmtTime(recorder.remainingSeconds) + ")" : "")
                                + "   " + panel.fmtSize(recorder.bytes)
                              : (recorder.status !== "" ? recorder.status : (recorder.available ? "" : "ffmpeg ontbreekt: opnemen kan niet"))
                    }
                }
                Text {
                    visible: recorder.recording
                    color: "#b0b4bb"
                    font.pixelSize: panel.unit * 2
                    elide: Text.ElideMiddle
                    width: content.width - stopButton.width - panel.unit * 4
                    text: recorder.status + "   ·   " + recorder.file
                }
            }
        }
        Text {
            id: message
            color: "#ffb74d"
            font.pixelSize: panel.unit * 2.2
            visible: text !== ""
        }

        // Eerdere opnames
        Text {
            color: "#9fb4d0"
            font.pixelSize: panel.unit * 2.2
            text: "Opnames in deze map" + (recorder.recordings.length > 0 ? "   ·   OK afspelen   ·   F2 / X verwijderen" : "")
        }
        ListView {
            id: list
            width: content.width
            height: panel.height - y - panel.unit * 10
            clip: true
            model: recorder.recordings
            spacing: panel.unit * 0.4
            KeyNavigation.up: recorder.recording ? stopButton : startButton
            Keys.onReturnPressed: if (currentItem) recorder.play(currentItem.modelData.path)
            Keys.onEnterPressed: if (currentItem) recorder.play(currentItem.modelData.path)
            Keys.onPressed: (event) => {
                if ((event.key === Qt.Key_F2 || event.key === Qt.Key_Menu) && currentItem) {
                    if (panel.confirmDelete === currentIndex) {
                        recorder.remove(currentItem.modelData.path)
                        panel.confirmDelete = -1
                    } else {
                        panel.confirmDelete = currentIndex
                    }
                    event.accepted = true
                }
            }
            Text {
                visible: list.count === 0
                color: "#60646b"
                font.pixelSize: panel.unit * 2.4
                text: "Nog geen opnames"
            }
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool current: ListView.isCurrentItem && list.activeFocus
                width: list.width
                height: panel.unit * 6.5
                radius: panel.unit
                color: current ? "#ffffff" : (index % 2 ? "#14ffffff" : "transparent")
                MouseArea {
                    anchors.fill: parent
                    onClicked: { list.currentIndex = row.index; list.forceActiveFocus() }
                    onDoubleClicked: recorder.play(row.modelData.path)
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: panel.unit * 1.5
                    spacing: panel.unit * 3
                    Text {
                        width: list.width * 0.55
                        elide: Text.ElideRight
                        color: row.current ? "#202124" : "white"
                        font.pixelSize: panel.unit * 2.5
                        text: (row.modelData.busy ? "●  " : "") + row.modelData.name
                    }
                    Text {
                        width: list.width * 0.18
                        color: row.current ? "#5f6368" : "#b0b4bb"
                        font.pixelSize: panel.unit * 2.2
                        text: row.modelData.date
                    }
                    Text {
                        color: row.current ? "#5f6368" : "#b0b4bb"
                        font.pixelSize: panel.unit * 2.2
                        text: panel.confirmDelete === row.index ? "Nog eens F2 / X om te verwijderen" : panel.fmtSize(row.modelData.size)
                    }
                }
            }
        }
    }
}
