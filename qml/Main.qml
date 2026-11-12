// Startpagina van Bigscreen voor Windows: klok, snelknoppen, een rij met
// streamingdiensten en een raster met toepassingen. Volledig te bedienen met
// pijltjestoetsen, Enter en een gamepad.
// Eigen QtQuick-versie van containments/homescreen (die aan Plasma vastzit).
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Dialogs

Rectangle {
    id: root

    readonly property real unit: height / 100
    readonly property int columns: Math.max(3, Math.floor(width / (unit * 24)))

    // Model en rij van de tegel waarvoor het aanpas-menu of de bestandskiezer open staat
    property var editModel: appModel
    property int editRow: -1

    gradient: Gradient {
        GradientStop { position: 0.0; color: "#16233a" }
        GradientStop { position: 1.0; color: "#0b1220" }
    }

    function showToast(message) {
        toast.text = message
        toastTimer.restart()
    }

    function openTileMenu(model, row, focusItem) {
        if (row < 0) {
            return
        }
        editModel = model
        editRow = row
        const entries = [{ label: "Pictogram wijzigen…", action: "icon" }]
        if (model.hasCustomIcon(row)) {
            entries.push({ label: "Standaardpictogram herstellen", action: "icon-reset" })
        }
        entries.push({ label: "Van startpagina verwijderen", action: "hide" })
        entries.push({ label: "Annuleren", action: "" })
        menu.open(model.nameAt(row), entries, focusItem)
    }

    function openPersonalizeMenu() {
        const entries = [
            { label: "Tegel toevoegen…", action: "add" },
            { label: "Achtergrond kiezen…", action: "background" }
        ]
        if (appModel.background !== "") {
            entries.push({ label: "Standaardachtergrond herstellen", action: "background-reset" })
        }
        const hidden = appModel.hiddenCount + webModel.hiddenCount
        if (hidden > 0) {
            entries.push({ label: "Verwijderde tegels terugzetten (" + hidden + ")", action: "unhide" })
        }
        entries.push({ label: "Sluiten", action: "" })
        menu.open("Aanpassen", entries, quickRow)
    }

    function handleMenuAction(action) {
        if (action === "icon") {
            imageDialog.purpose = "icon"
            imageDialog.title = "Pictogram kiezen voor " + editModel.nameAt(editRow)
            imageDialog.open()
        } else if (action === "icon-reset") {
            editModel.clearCustomIcon(editRow)
        } else if (action === "hide") {
            const name = editModel.nameAt(editRow)
            editModel.hide(editRow)
            showToast(name + " verwijderd")
        } else if (action === "add") {
            addOverlay.open(quickRow)
        } else if (action === "background") {
            imageDialog.purpose = "background"
            imageDialog.title = "Achtergrond kiezen"
            imageDialog.open()
        } else if (action === "background-reset") {
            appModel.clearBackground()
        } else if (action === "unhide") {
            appModel.restoreHidden()
            webModel.restoreHidden()
            showToast("Alle tegels staan weer op de startpagina")
        }
    }

    function addTile(name, target) {
        // Een pad naar een bestand is een programma; al het andere een webadres
        const isFile = /^[a-zA-Z]:[\\/]/.test(target.trim()) || target.trim().startsWith("\\\\")
                       || target.trim().startsWith("\"") || target.trim().startsWith("file:")
        const ok = isFile ? appModel.addTile(name, target) : webModel.addTile(name, target)
        if (!ok) {
            showToast("Toevoegen mislukt: controleer het adres of pad (of de tegel bestaat al)")
        } else {
            showToast("Tegel toegevoegd")
        }
    }

    Component.onCompleted: {
        if (selfTest === "addtile") {
            addOverlay.open(quickRow)
        }
    }

    // Eigen achtergrond, met een donkere laag erover zodat tekst leesbaar blijft
    Image {
        anchors.fill: parent
        visible: appModel.background !== ""
        source: appModel.background
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        Rectangle { anchors.fill: parent; color: "#66000000" }
    }

    ListModel {
        id: quickModel
        ListElement { label: "Instellingen"; code: 0xE713; uri: "ms-settings:" }
        ListElement { label: "Wifi"; code: 0xE701; uri: "ms-settings:network-wifi" }
        ListElement { label: "Bluetooth"; code: 0xE702; uri: "ms-settings:bluetooth" }
        ListElement { label: "Beeldscherm"; code: 0xE7F4; uri: "ms-settings:display" }
        ListElement { label: "Geluid"; code: 0xE767; uri: "ms-settings:sound" }
        ListElement { label: "Aanpassen"; code: 0xE771; uri: "personalize" }
        ListElement { label: "Afsluiten"; code: 0xE7E8; uri: "" }
    }

    // --- Kop: titel links, klok en datum rechts ---
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.unit * 3
        height: root.unit * 8

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
                font.pixelSize: root.unit * 4.5
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

    // --- Snelknoppen: altijd allemaal zichtbaar, breedte verdeeld over het scherm ---
    ListView {
        id: quickRow
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.unit * 3
        anchors.rightMargin: root.unit * 3
        anchors.topMargin: root.unit
        height: root.unit * 7
        orientation: ListView.Horizontal
        model: quickModel
        keyNavigationEnabled: true
        interactive: false

        function trigger(index) {
            const item = quickModel.get(index)
            if (item.uri === "") {
                Qt.quit()
            } else if (item.uri === "personalize") {
                root.openPersonalizeMenu()
            } else {
                appModel.openUri(item.uri)
                root.showToast(item.label + " openen…")
            }
        }

        delegate: QuickTile {
            required property int code
            glyph: String.fromCharCode(code)
            width: quickRow.width / quickModel.count
            height: quickRow.height
            selected: quickRow.activeFocus && quickRow.currentIndex === index
            onActivated: { quickRow.currentIndex = index; quickRow.trigger(index) }
            onHovered: { if (!menu.visible && !addOverlay.visible) { quickRow.currentIndex = index; quickRow.forceActiveFocus() } }
        }

        Keys.onReturnPressed: trigger(currentIndex)
        Keys.onEnterPressed: trigger(currentIndex)
        Keys.onDownPressed: (webModel.count > 0 ? streamRow : appGrid).forceActiveFocus()
    }

    // --- Streaming ---
    Text {
        id: streamTitle
        anchors.top: quickRow.bottom
        anchors.left: parent.left
        anchors.topMargin: root.unit * 2
        anchors.leftMargin: root.unit * 4
        visible: webModel.count > 0
        height: visible ? implicitHeight : 0
        color: "#9fb4d0"
        font.pixelSize: root.unit * 2.4
        text: "Streaming (" + webModel.count + ")"
    }

    ListView {
        id: streamRow
        anchors.top: streamTitle.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.unit * 3
        anchors.rightMargin: root.unit * 3
        visible: webModel.count > 0
        height: visible ? root.unit * 19 : 0
        orientation: ListView.Horizontal
        model: webModel
        keyNavigationEnabled: true
        clip: true
        highlightMoveDuration: 150
        preferredHighlightBegin: width * 0.1
        preferredHighlightEnd: width * 0.9
        highlightRangeMode: ListView.ApplyRange

        function trigger(index) {
            if (index < 0) {
                return
            }
            const name = webModel.nameAt(index)
            root.showToast(webModel.launch(index) ? name + " openen… (sluiten met Alt+F4)" : name + " kon niet geopend worden")
        }

        delegate: AppTile {
            width: streamRow.height * 1.2
            height: streamRow.height
            selected: streamRow.activeFocus && streamRow.currentIndex === index
            onActivated: { streamRow.currentIndex = index; streamRow.trigger(index) }
            onHovered: { if (!menu.visible && !addOverlay.visible) { streamRow.currentIndex = index; streamRow.forceActiveFocus() } }
            onMenuRequested: { streamRow.currentIndex = index; root.openTileMenu(webModel, index, streamRow) }
        }

        Keys.onReturnPressed: trigger(currentIndex)
        Keys.onEnterPressed: trigger(currentIndex)
        Keys.onMenuPressed: root.openTileMenu(webModel, currentIndex, streamRow)
        Keys.onUpPressed: quickRow.forceActiveFocus()
        Keys.onDownPressed: appGrid.forceActiveFocus()
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_F2) {
                root.openTileMenu(webModel, currentIndex, streamRow)
                event.accepted = true
            }
        }
    }

    // --- Raster met toepassingen ---
    Text {
        id: sectionTitle
        anchors.top: streamRow.bottom
        anchors.left: parent.left
        anchors.topMargin: root.unit * 1.5
        anchors.leftMargin: root.unit * 4
        color: "#9fb4d0"
        font.pixelSize: root.unit * 2.4
        text: "Toepassingen (" + appModel.count + ")"
    }

    GridView {
        id: appGrid
        anchors.top: sectionTitle.bottom
        anchors.bottom: hint.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.unit * 3
        anchors.rightMargin: root.unit * 3
        anchors.topMargin: root.unit * 0.5
        anchors.bottomMargin: root.unit
        cellWidth: Math.floor(width / root.columns)
        cellHeight: cellWidth * 0.8
        model: appModel
        focus: true
        clip: true
        keyNavigationEnabled: true
        highlightMoveDuration: 150
        // Ruimte houden zodat de geselecteerde tegel niet tegen de rand plakt
        preferredHighlightBegin: cellHeight * 0.1
        preferredHighlightEnd: height - cellHeight * 0.1
        highlightRangeMode: GridView.ApplyRange

        function trigger(index) {
            if (index < 0) {
                return
            }
            const name = appModel.nameAt(index)
            root.showToast(appModel.launch(index) ? name + " starten…" : name + " kon niet gestart worden")
        }

        delegate: AppTile {
            width: appGrid.cellWidth
            height: appGrid.cellHeight
            selected: appGrid.activeFocus && appGrid.currentIndex === index
            onActivated: { appGrid.currentIndex = index; appGrid.trigger(index) }
            onHovered: { if (!menu.visible && !addOverlay.visible) { appGrid.currentIndex = index; appGrid.forceActiveFocus() } }
            onMenuRequested: { appGrid.currentIndex = index; root.openTileMenu(appModel, index, appGrid) }
        }

        Keys.onReturnPressed: trigger(currentIndex)
        Keys.onEnterPressed: trigger(currentIndex)
        Keys.onMenuPressed: root.openTileMenu(appModel, currentIndex, appGrid)
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_F2) {
                root.openTileMenu(appModel, currentIndex, appGrid)
                event.accepted = true
            }
        }
        Keys.onUpPressed: (event) => {
            if (currentIndex < root.columns) {
                (webModel.count > 0 ? streamRow : quickRow).forceActiveFocus()
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
        anchors.bottomMargin: root.unit * 1.5
        color: "#6f819c"
        font.pixelSize: root.unit * 2
        text: (gamepad.connectedCount > 0 ? "Controller verbonden  ·  " : "")
              + "Pijltjes / D-pad: navigeren  ·  Enter / A: openen  ·  F2, rechtermuisknop of X: tegel aanpassen"
    }

    // --- Korte melding ---
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
        z: 200
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            id: toast
            anchors.centerIn: parent
            color: "white"
            font.pixelSize: root.unit * 2.6
        }
    }
    Timer { id: toastTimer; interval: 3000 }

    // --- Dialogen ---
    FileDialog {
        id: imageDialog
        property string purpose
        nameFilters: ["Afbeeldingen (*.png *.jpg *.jpeg *.bmp *.gif *.webp *.ico *.svg)"]
        onAccepted: {
            const ok = purpose === "icon" ? root.editModel.setCustomIcon(root.editRow, selectedFile)
                                          : appModel.setBackground(selectedFile)
            if (!ok) {
                root.showToast("Deze afbeelding kon niet gebruikt worden")
            }
        }
    }

    FileDialog {
        id: programDialog
        title: "Programma kiezen"
        nameFilters: ["Programma's en snelkoppelingen (*.exe *.lnk *.bat *.cmd *.url)", "Alle bestanden (*)"]
        onAccepted: addOverlay.targetText = selectedFile.toString()
    }

    MenuOverlay {
        id: menu
        onChosen: (action) => root.handleMenuAction(action)
    }

    AddTileOverlay {
        id: addOverlay
        onAccepted: (name, target) => root.addTile(name, target)
        onBrowseRequested: programDialog.open()
    }
}
