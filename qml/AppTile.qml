// Tegel voor een toepassing in het raster.
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick

Item {
    id: tile

    property string name
    property string iconSource
    property bool selected: false
    signal activated()
    signal hovered()

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: parent.width * 0.06
        radius: width * 0.08
        color: tile.selected ? "#3d6fb4" : "#22ffffff"
        border.width: tile.selected ? Math.max(3, width * 0.02) : 0
        border.color: "white"
        scale: tile.selected ? 1.08 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 120 } }

        Image {
            id: icon
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.14
            width: parent.height * 0.5
            height: width
            sourceSize: Qt.size(256, 256)
            source: tile.iconSource
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: parent.width * 0.06
            horizontalAlignment: Text.AlignHCenter
            color: "white"
            font.pixelSize: Math.max(12, parent.height * 0.1)
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
            text: tile.name
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: tile.hovered()
        onClicked: tile.activated()
    }
}
