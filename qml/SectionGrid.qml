// Een rij op de startpagina (Video, Muziek, Podcasts, Media):
// titel met tegels eronder. De hoogte groeit mee met het aantal tegels; de
// startpagina scrolt. Bij de rand van de rij geeft hij de focus door.
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick

Item {
    id: section

    property string title
    property var model: null
    property int columns: 5
    property real unit: 10
    // Mag de muis de selectie overnemen? (bij open venster of stilstaande muis niet)
    property var canHover: function() { return true }
    readonly property alias grid: grid
    readonly property int count: model ? model.count : 0

    signal exitUp(int column)
    signal exitDown(int column)
    signal launchRequested(int index)
    signal menuRequested(int index)
    signal tileFocused()

    // Focus binnenkomen in een bepaalde kolom (van boven of van onder)
    function enter(column, fromBelow) {
        if (count === 0) {
            return false
        }
        const rows = Math.ceil(count / columns)
        const row = fromBelow ? rows - 1 : 0
        grid.currentIndex = Math.min(count - 1, row * columns + Math.max(0, column))
        grid.forceActiveFocus()
        return true
    }

    visible: count > 0
    height: visible ? label.height + grid.height + unit * 1.5 : 0

    Text {
        id: label
        anchors.left: parent.left
        anchors.leftMargin: section.unit * 1.5
        color: "white"
        font.pixelSize: section.unit * 2.6
        font.weight: Font.DemiBold
        text: section.title
    }

    GridView {
        id: grid
        readonly property real pad: section.unit * 2.2
        anchors.top: label.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: section.unit * 0.5
        leftMargin: pad
        rightMargin: pad
        topMargin: pad * 0.6
        bottomMargin: pad * 0.6
        cellWidth: Math.floor((width - pad * 2) / section.columns)
        cellHeight: Math.floor(cellWidth * 0.46)
        height: Math.ceil(section.count / section.columns) * cellHeight + pad * 1.2
        interactive: false
        keyNavigationEnabled: true
        highlightMoveDuration: 150
        model: section.model

        onActiveFocusChanged: if (activeFocus) section.tileFocused()
        onCurrentIndexChanged: if (activeFocus) section.tileFocused()

        delegate: BannerTile {
            width: grid.cellWidth
            height: grid.cellHeight
            selected: grid.activeFocus && grid.currentIndex === index
            onActivated: {
                grid.currentIndex = index
                grid.forceActiveFocus()
                section.launchRequested(index)
            }
            onHovered: {
                if (section.canHover()) {
                    grid.currentIndex = index
                    grid.forceActiveFocus()
                }
            }
            onMenuRequested: {
                grid.currentIndex = index
                section.menuRequested(index)
            }
            // Slepen: de tegel neemt de plek in van de tegel waar de muis boven hangt
            onDragMoved: (x, y) => {
                const pos = mapToItem(grid.contentItem, x, y)
                const to = grid.indexAt(pos.x, pos.y)
                if (to >= 0 && to !== index) {
                    section.model.move(index, to)
                    grid.currentIndex = to
                }
            }
        }

        move: Transition { NumberAnimation { properties: "x,y"; duration: 160; easing.type: Easing.OutCubic } }
        displaced: Transition { NumberAnimation { properties: "x,y"; duration: 160; easing.type: Easing.OutCubic } }

        Keys.onReturnPressed: section.launchRequested(currentIndex)
        Keys.onEnterPressed: section.launchRequested(currentIndex)
        Keys.onMenuPressed: section.menuRequested(currentIndex)
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_F2) {
                section.menuRequested(currentIndex)
                event.accepted = true
            }
        }
        Keys.onUpPressed: (event) => {
            if (currentIndex < section.columns) {
                section.exitUp(currentIndex % section.columns)
            } else {
                event.accepted = false
            }
        }
        Keys.onDownPressed: (event) => {
            const column = currentIndex % section.columns
            const lastRowStart = Math.floor((section.count - 1) / section.columns) * section.columns
            if (currentIndex >= lastRowStart) {
                section.exitDown(column)
            } else if (currentIndex + section.columns > section.count - 1) {
                currentIndex = section.count - 1 // onvolledige laatste rij
            } else {
                event.accepted = false
            }
        }
    }
}
