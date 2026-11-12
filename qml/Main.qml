// Startpagina van Bigscreen voor Windows: klok, snelknoppen en een raster met
// toepassingen, volledig te bedienen met pijltjestoetsen, Enter en een gamepad.
// Eigen QtQuick-versie van containments/homescreen (die aan Plasma vastzit).
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick

Rectangle {
    id: root

    readonly property real unit: height / 100
    readonly property int columns: Math.max(3, Math.floor(width / (unit * 24)))

    gradient: Gradient {
        GradientStop { position: 0.0; color: "#16233a" }
        GradientStop { position: 1.0; color: "#0b1220" }
    }

    function showToast(message) {
        toast.text = message
        toastTimer.restart()
    }

    ListModel {
        id: quickModel
        ListElement { label: "Instellingen"; glyph: ""; uri: "ms-settings:" }
        ListElement { label: "Wifi"; glyph: ""; uri: "ms-settings:network-wifi" }
        ListElement { label: "Bluetooth"; glyph: ""; uri: "ms-settings:bluetooth" }
        ListElement { label: "Beeldscherm"; glyph: ""; uri: "ms-settings:display" }
        ListElement { label: "Geluid"; glyph: ""; uri: "ms-settings:sound" }
        ListElement { label: "Afsluiten"; glyph: ""; uri: "" }
    }

    // --- Kop: titel links, klok en datum rechts ---
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.unit * 4
        height: root.unit * 9

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: "white"
            font.pixelSize: root.unit * 5
            font.weight: Font.Light
            text: "Bigscreen"
        }

        Column {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Text {
                id: clock
                anchors.right: parent.right
                color: "white"
                font.pixelSize: root.unit * 5
            }
            Text {
                id: dateLabel
                anchors.right: parent.right
                color: "#9fb4d0"
                font.pixelSize: root.unit * 2.2
            }
        }
    }

    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            const now = new Date()
            clock.text = Qt.formatTime(now, "HH:mm")
            dateLabel.text = now.toLocaleDateString(Qt.locale(), "dddd d MMMM")
        }
    }

    // --- Snelknoppen ---
    ListView {
        id: quickRow
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.unit * 4
        anchors.rightMargin: root.unit * 4
        anchors.topMargin: root.unit * 2
        height: root.unit * 8
        orientation: ListView.Horizontal
        spacing: root.unit
        model: quickModel
        keyNavigationEnabled: true
        clip: true

        function trigger(index) {
            const item = quickModel.get(index)
            if (item.uri === "") {
                Qt.quit()
            } else {
                appModel.openUri(item.uri)
                root.showToast(item.label + " openen…")
            }
        }

        delegate: QuickTile {
            required property int index
            required property string label
            required property string glyph
            width: root.unit * 30
            height: quickRow.height
            selected: quickRow.activeFocus && quickRow.currentIndex === index
            onActivated: { quickRow.currentIndex = index; quickRow.trigger(index) }
            onHovered: { quickRow.currentIndex = index; quickRow.forceActiveFocus() }
        }

        Keys.onReturnPressed: trigger(currentIndex)
        Keys.onEnterPressed: trigger(currentIndex)
        Keys.onDownPressed: appGrid.forceActiveFocus()
    }

    Text {
        id: sectionTitle
        anchors.top: quickRow.bottom
        anchors.left: parent.left
        anchors.topMargin: root.unit * 3
        anchors.leftMargin: root.unit * 5
        color: "#9fb4d0"
        font.pixelSize: root.unit * 2.6
        text: "Toepassingen (" + appModel.count + ")"
    }

    // --- Raster met toepassingen ---
    GridView {
        id: appGrid
        anchors.top: sectionTitle.bottom
        anchors.bottom: hint.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.unit * 4
        anchors.rightMargin: root.unit * 4
        anchors.topMargin: root.unit
        anchors.bottomMargin: root.unit
        cellWidth: Math.floor(width / root.columns)
        cellHeight: cellWidth * 0.8
        model: appModel
        focus: true
        clip: true
        keyNavigationEnabled: true
        highlightMoveDuration: 150
        // Ruimte houden zodat de geselecteerde tegel niet tegen de rand plakt
        preferredHighlightBegin: cellHeight * 0.2
        preferredHighlightEnd: height - cellHeight * 1.2
        highlightRangeMode: GridView.ApplyRange

        function trigger(index) {
            if (index < 0) {
                return
            }
            const name = appModel.data(appModel.index(index, 0), Qt.UserRole + 1)
            if (appModel.launch(index)) {
                root.showToast(name + " starten…")
            } else {
                root.showToast(name + " kon niet gestart worden")
            }
        }

        delegate: AppTile {
            required property int index
            required property string name
            required property string iconSource
            width: appGrid.cellWidth
            height: appGrid.cellHeight
            selected: appGrid.activeFocus && appGrid.currentIndex === index
            onActivated: { appGrid.currentIndex = index; appGrid.trigger(index) }
            onHovered: { appGrid.currentIndex = index; appGrid.forceActiveFocus() }
        }

        Keys.onReturnPressed: trigger(currentIndex)
        Keys.onEnterPressed: trigger(currentIndex)
        Keys.onUpPressed: (event) => {
            if (currentIndex < root.columns) {
                quickRow.forceActiveFocus()
            } else {
                event.accepted = false
            }
        }
    }

    Text {
        anchors.centerIn: appGrid
        visible: appModel.count === 0
        color: "#9fb4d0"
        font.pixelSize: root.unit * 3
        text: "Geen toepassingen gevonden in het Startmenu"
    }

    Text {
        id: hint
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: root.unit * 2
        color: "#6f819c"
        font.pixelSize: root.unit * 2
        text: (gamepad.connectedCount > 0 ? "Controller verbonden  ·  " : "")
              + "Pijltjes / D-pad: navigeren  ·  Enter / A: openen  ·  Afsluiten via de knop bovenaan of Alt+F4"
    }

    // --- Korte melding bij starten ---
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.unit * 8
        width: toast.implicitWidth + root.unit * 6
        height: root.unit * 7
        radius: height / 2
        color: "#e6000000"
        opacity: toastTimer.running ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            id: toast
            anchors.centerIn: parent
            color: "white"
            font.pixelSize: root.unit * 2.6
        }
    }
    Timer { id: toastTimer; interval: 2500 }
}
