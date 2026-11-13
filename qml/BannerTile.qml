// Brede tegel: logo met naam ernaast op een vlak in de kleur van het logo.
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick

Item {
    id: tile

    // Ingevuld door de view vanuit het model
    required property int index
    required property string name
    required property string iconSource
    required property color accent

    property bool selected: false
    // "glyph:<teken>": pictogram uit het Windows-lettertype in plaats van een afbeelding
    readonly property bool isGlyph: iconSource.startsWith("glyph:")
    signal activated()
    signal menuRequested()
    signal hovered()
    // Slepen: linkermuisknop ingedrukt houden en de tegel naar een andere plek bewegen
    property bool dragging: false
    signal dragMoved(real x, real y)

    // Gekozen tegel komt boven zijn buren te liggen
    z: dragging ? 3 : selected ? 2 : 0

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: parent.height * 0.06
        radius: height * 0.06
        color: tile.accent
        border.width: tile.selected ? Math.max(3, height * 0.035) : 0
        border.color: "white"
        scale: tile.dragging ? 1.28 : tile.selected ? 1.2 : 1.0
        opacity: tile.dragging ? 0.85 : 1.0
        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

        // Lichte glans bovenin, zodat het vlak niet vlak oogt
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#24ffffff" }
                GradientStop { position: 0.6; color: "#00ffffff" }
            }
        }

        Row {
            id: content
            anchors.centerIn: parent
            spacing: card.height * 0.1

            Item {
                width: card.height * 0.56
                height: width
                anchors.verticalCenter: parent.verticalCenter

                // Nog geen pictogram: beginletter
                Text {
                    anchors.centerIn: parent
                    visible: !tile.isGlyph && (tile.iconSource === "" || icon.status === Image.Error)
                    color: "white"
                    font.pixelSize: parent.height * 0.8
                    font.weight: Font.Bold
                    text: tile.name.charAt(0).toUpperCase()
                }
                Text {
                    anchors.centerIn: parent
                    visible: tile.isGlyph
                    color: "white"
                    font.family: "Segoe MDL2 Assets"
                    font.pixelSize: parent.height * 0.8
                    text: tile.isGlyph ? tile.iconSource.substring(6) : ""
                }
                Image {
                    id: icon
                    anchors.fill: parent
                    sourceSize: Qt.size(256, 256)
                    source: tile.isGlyph ? "" : tile.iconSource
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, card.width - card.height * 0.56 - card.height * 0.34)
                color: "white"
                font.pixelSize: card.height * 0.2
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: tile.name
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        // Tijdens het slepen mag de lijst de muis niet overnemen om te scrollen
        preventStealing: tile.dragging
        onEntered: tile.hovered()
        onClicked: (mouse) => {
            if (mouse.wasHeld) {
                return
            }
            if (mouse.button === Qt.RightButton) {
                tile.menuRequested()
            } else {
                tile.activated()
            }
        }
        onPressAndHold: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                tile.dragging = true
            }
        }
        onPositionChanged: (mouse) => {
            if (tile.dragging) {
                tile.dragMoved(mouse.x, mouse.y)
            }
        }
        onReleased: tile.dragging = false
        onCanceled: tile.dragging = false
    }
}
