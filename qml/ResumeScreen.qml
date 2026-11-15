// Tegel "Verder kijken" (rij Media, naast Schilderij): films en afleveringen die je half hebt gezien.
// Enter = verder kijken, Menu = uit de lijst halen, Esc/B = terug.
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick

FocusScope {
    id: screen

    readonly property real unit: height / 100
    property Item returnFocusTo: null
    signal playRequested(int row)
    signal menuRequested(int row)

    anchors.fill: parent
    visible: false
    z: 55

    function open(focusItem) {
        returnFocusTo = focusItem
        grid.currentIndex = 0
        visible = true
        grid.forceActiveFocus()
        console.info("Resume screen:", resume.count)
    }

    function close() {
        visible = false
        if (returnFocusTo) returnFocusTo.forceActiveFocus()
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back || event.key === Qt.Key_Backspace) {
            close()
            event.accepted = true
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#0b0c0f"
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
    }

    Text {
        id: title
        x: screen.unit * 5
        y: screen.unit * 4
        text: "Verder kijken"
        color: "white"
        font.pixelSize: screen.unit * 4.5 * appModel.fontScale
        font.weight: Font.DemiBold
    }

    Text {
        anchors.left: title.left
        anchors.top: title.bottom
        anchors.topMargin: screen.unit * 3
        visible: resume.count === 0
        text: "Nog niets om verder te kijken."
        color: "#a8acb3"
        font.pixelSize: screen.unit * 2.8 * appModel.fontScale
    }

    GridView {
        id: grid
        anchors.top: title.bottom
        anchors.topMargin: screen.unit * 3
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: hints.top
        anchors.leftMargin: screen.unit * 4
        anchors.rightMargin: screen.unit * 4
        cellWidth: Math.floor(width / 3)
        cellHeight: Math.floor(cellWidth * 0.62)
        clip: true
        keyNavigationEnabled: true
        highlightMoveDuration: 150
        model: resume

        delegate: BannerTile {
            width: grid.cellWidth
            height: grid.cellHeight
            selected: grid.activeFocus && grid.currentIndex === index
            backdrop: resume.backdropAt(index + resume.revision * 0)
            subtitle: resume.subtitleAt(index)
            progress: resume.progressAt(index)
            onActivated: { grid.currentIndex = index; screen.playRequested(index) }
            onMenuRequested: { grid.currentIndex = index; screen.menuRequested(index) }
            onHovered: { grid.currentIndex = index; grid.forceActiveFocus() }
        }

        Keys.onReturnPressed: screen.playRequested(currentIndex)
        Keys.onEnterPressed: screen.playRequested(currentIndex)
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Menu) {
                screen.menuRequested(currentIndex)
                event.accepted = true
            }
        }
    }

    HintBar {
        id: hints
        anchors.left: parent.left
        anchors.leftMargin: screen.unit * 5
        anchors.bottom: parent.bottom
        anchors.bottomMargin: screen.unit * 3
        unit: screen.unit
        items: [{ pad: "A", key: "Enter", label: "Verder kijken" }, { pad: "X", key: "Menu", label: "Uit de lijst" },
                { pad: "B", key: "Esc", label: "Terug" }]
    }
}
