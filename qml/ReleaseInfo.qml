// Instellingen → Release-info: geïnstalleerde versie en wat er per versie nieuw is
// (uit releasenotes.json; bij elke nieuwe versie bovenaan aanvullen).
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick

FocusScope {
    id: info

    readonly property real unit: height / 100
    property Item returnFocusTo: null
    property var versions: []

    anchors.fill: parent
    visible: false
    z: 120

    function open(focusItem) {
        returnFocusTo = focusItem
        const xhr = new XMLHttpRequest()
        xhr.open("GET", "qrc:/releasenotes.json", false)
        xhr.send()
        try {
            versions = JSON.parse(xhr.responseText)
        } catch (e) {
            versions = []
        }
        console.info("Release info:", versions.length, "versions")
        flick.contentY = 0
        visible = true
        flick.forceActiveFocus()
    }

    function close() {
        visible = false
        if (returnFocusTo) returnFocusTo.forceActiveFocus()
    }

    Rectangle {
        anchors.fill: parent
        color: "#0b0c0f"
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
    }

    Column {
        id: head
        x: info.unit * 6
        y: info.unit * 5
        spacing: info.unit * 1
        Text {
            text: "Release-info"
            color: "white"
            font.pixelSize: info.unit * 4.5 * appModel.fontScale
            font.weight: Font.DemiBold
        }
        Text {
            text: "Geïnstalleerd: Kijkluister " + updater.current
                  + (updater.updateAvailable ? "   ·   Nieuwste versie: " + updater.latest : "   ·   Dit is de nieuwste versie")
            color: "#d5d8dc"
            font.pixelSize: info.unit * 2.6 * appModel.fontScale
        }
    }

    Flickable {
        id: flick
        anchors.top: head.bottom
        anchors.topMargin: info.unit * 3
        anchors.bottom: hints.top
        anchors.bottomMargin: info.unit * 2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: info.unit * 6
        anchors.rightMargin: info.unit * 6
        contentHeight: list.height
        clip: true
        Behavior on contentY { NumberAnimation { duration: 150 } }
        Keys.onUpPressed: contentY = Math.max(0, contentY - info.unit * 12)
        Keys.onDownPressed: contentY = Math.max(0, Math.min(contentHeight - height, contentY + info.unit * 12))
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back || event.key === Qt.Key_Backspace
                    || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                info.close()
                event.accepted = true
            }
        }

        Column {
            id: list
            width: flick.width
            spacing: info.unit * 3
            Repeater {
                model: info.versions
                Column {
                    required property var modelData
                    width: list.width
                    spacing: info.unit * 0.8
                    Row {
                        spacing: info.unit * 1.5
                        Text {
                            text: "Versie " + modelData.version
                            color: "white"
                            font.pixelSize: info.unit * 3.2 * appModel.fontScale
                            font.weight: Font.DemiBold
                        }
                        Rectangle {
                            visible: modelData.version === updater.current
                            anchors.verticalCenter: parent.verticalCenter
                            width: badge.implicitWidth + info.unit * 2
                            height: info.unit * 3.2
                            radius: height / 2
                            color: "#2e7d32"
                            Text {
                                id: badge
                                anchors.centerIn: parent
                                text: "Geïnstalleerd"
                                color: "white"
                                font.pixelSize: info.unit * 1.8 * appModel.fontScale
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.date || ""
                            color: "#a8acb3"
                            font.pixelSize: info.unit * 2.2 * appModel.fontScale
                        }
                    }
                    Repeater {
                        model: modelData.notes
                        Text {
                            required property string modelData
                            width: list.width
                            wrapMode: Text.WordWrap
                            text: "•  " + modelData
                            color: "#e6e8eb"
                            font.pixelSize: info.unit * 2.4 * appModel.fontScale
                            leftPadding: info.unit
                        }
                    }
                }
            }
        }
    }

    HintBar {
        id: hints
        anchors.left: parent.left
        anchors.leftMargin: info.unit * 6
        anchors.bottom: parent.bottom
        anchors.bottomMargin: info.unit * 3
        unit: info.unit
        items: [{ pad: "▲ ▼", key: "▲ ▼", label: "Lezen" }, { pad: "B", key: "Esc", label: "Terug" }]
    }
}
