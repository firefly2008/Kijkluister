// Tegel voor een toepassing in het raster.
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick

Item {
    id: tile

    // Ingevuld door de view vanuit het model
    required property int index
    required property string name
    required property string iconSource
    property bool selected: false
    signal activated()
    signal menuRequested()
    signal hovered()

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: parent.width * 0.06
        radius: height * 0.09
        color: tile.selected ? "#3b3e45" : "#cc1f2126"
        border.width: tile.selected ? Math.max(3, height * 0.025) : 0
        border.color: "white"
        scale: tile.selected ? 1.09 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 120 } }

        // Nog geen pictogram (site-logo niet opgehaald): gekleurd vlak met beginletter
        Rectangle {
            anchors.fill: icon
            visible: tile.iconSource === "" || icon.status === Image.Error
            radius: width * 0.2
            color: Qt.hsla((tile.name.length * 47 % 360) / 360, 0.45, 0.4, 1)
            Text {
                anchors.centerIn: parent
                color: "white"
                font.pixelSize: parent.height * 0.55
                text: tile.name.charAt(0).toUpperCase()
            }
        }

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
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: tile.hovered()
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                tile.menuRequested()
            } else {
                tile.activated()
            }
        }
        onPressAndHold: tile.menuRequested()
    }
}
