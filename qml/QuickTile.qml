// Ronde snelknop in de bovenste rij (instellingen, wifi, afsluiten, ...).
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick

Item {
    id: tile

    property string label
    property string glyph
    property bool selected: false
    signal activated()
    signal hovered()

    Rectangle {
        anchors.fill: parent
        anchors.margins: 6
        radius: height / 2
        color: tile.selected ? "#3d6fb4" : "#22ffffff"
        border.width: tile.selected ? 3 : 0
        border.color: "white"
        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
            anchors.centerIn: parent
            spacing: parent.height * 0.25

            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: "white"
                font.family: "Segoe MDL2 Assets"
                font.pixelSize: tile.height * 0.36
                text: tile.glyph
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: "white"
                font.pixelSize: tile.height * 0.3
                text: tile.label
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: tile.hovered()
        onClicked: tile.activated()
    }
}
