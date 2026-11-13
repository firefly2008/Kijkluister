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
    readonly property int columns: Math.max(4, Math.floor(width / (unit * 25)))

    // Model en rij van de tegel waarvoor het aanpas-menu of de bestandskiezer open staat
    property var editModel: appModel
    property int editRow: -1

    color: "#0b0c0f"

    // Naam en soort van de tegel die nu focus heeft (voor het grote tekstvlak bovenaan)
    readonly property string focusName: streamGrid.activeFocus ? webModel.nameAt(streamGrid.currentIndex)
                                       : appGrid.activeFocus ? appModel.nameAt(appGrid.currentIndex)
                                       : quickRow.activeFocus ? quickModel.get(quickRow.currentIndex).label : ""
    readonly property string focusKind: streamGrid.activeFocus ? "Streaming  ·  Enter om te openen"
                                       : appGrid.activeFocus ? "Media  ·  Enter om te openen"
                                       : quickRow.activeFocus ? "Instellingen" : ""
    // (revision in de binding: opnieuw opvragen zodra een logo binnen is of wijzigt)
    readonly property string focusIconRaw: streamGrid.activeFocus ? (webModel.revision, webModel.iconAt(streamGrid.currentIndex))
                                          : appGrid.activeFocus ? (appModel.revision, appModel.iconAt(appGrid.currentIndex)) : ""
    // Pictogrammen uit het lettertype (Films, Series) niet als afbeelding laden
    readonly property string focusIcon: focusIconRaw.startsWith("glyph:") ? "" : focusIconRaw
    // Achtergrondkleur: de kleur van het logo van de streamingdienst met focus
    readonly property color accent: streamGrid.activeFocus && streamGrid.currentIndex >= 0
                                    ? (webModel.revision, webModel.accentAt(streamGrid.currentIndex)) : "#1d3557"
    readonly property bool heroShown: appModel.showHero

    // Achtergrond: neemt de kleur van de gekozen streamingdienst aan, naar onder donker
    Rectangle {
        anchors.fill: parent
        visible: appModel.background === ""
        color: root.accent
        Behavior on color { ColorAnimation { duration: 450 } }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#300b0c0f" }
                GradientStop { position: 0.45; color: "#b00b0c0f" }
                GradientStop { position: 1.0; color: "#f20b0c0f" }
            }
        }
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
        for (const dir of ["left", "right", "up", "down"]) {
            if (root.moveLimit(model, row, dir) > 0) {
                entries.push({ label: root.moveLabels[dir] + " verplaatsen…", action: "move-" + dir })
            }
        }
        entries.push({ label: "Van startpagina verwijderen", action: "hide" })
        entries.push({ label: "Annuleren", action: "" })
        menu.open(model.nameAt(row), entries, focusItem)
    }

    readonly property var moveLabels: ({ left: "Naar links", right: "Naar rechts", up: "Naar boven", down: "Naar onder" })

    // Hoeveel plaatsen een tegel maximaal kan schuiven (omhoog/omlaag: in rijen)
    function moveLimit(model, row, dir) {
        const last = model.count - 1
        if (dir === "left") return row
        if (dir === "right") return last - row
        if (dir === "up") return Math.floor(row / root.columns)
        return Math.ceil((last - row) / root.columns)
    }

    function moveTile(model, row, dir, places) {
        const step = dir === "left" ? -1 : dir === "right" ? 1 : dir === "up" ? -root.columns : root.columns
        const to = Math.max(0, Math.min(model.count - 1, row + step * places))
        if (to === row) {
            return
        }
        model.move(row, to)
        const grid = model === webModel ? streamGrid : appGrid
        grid.currentIndex = to
        grid.forceActiveFocus()
    }

    function openPersonalizeMenu() {
        const entries = [
            { label: "Tegel toevoegen…", action: "add" },
            { label: "Achtergrond kiezen…", action: "background" },
            { label: appModel.showHero ? "Grote naam en logo linksboven verbergen" : "Grote naam en logo linksboven tonen", action: "toggle-hero" }
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
        } else if (action.startsWith("move-")) {
            const dir = action.substring(5)
            const grid = editModel === webModel ? streamGrid : appGrid
            placesPicker.open(editModel.nameAt(editRow) + ": " + moveLabels[dir].toLowerCase(),
                              dir === "up" || dir === "down" ? "rijen" : "plaatsen",
                              moveLimit(editModel, editRow, dir), grid)
            placesPicker.model = editModel
            placesPicker.row = editRow
            placesPicker.direction = dir
        } else if (action === "toggle-hero") {
            appModel.showHero = !appModel.showHero
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
        } else if (selfTest === "podcasts") {
            webModel.category = "podcasts"
            streamTitle.forceActiveFocus()
        } else if (selfTest === "moveask") {
            streamGrid.currentIndex = 2
            streamGrid.forceActiveFocus()
            editModel = webModel
            editRow = 2
            handleMenuAction("move-down")
        } else if (selfTest === "library") {
            libraryScreen.open("shows", appGrid)
        } else if (selfTest === "librarymovies") {
            libraryScreen.open("movies", appGrid)
        } else if (selfTest === "librarydetail") {
            libraryScreen.autoOpen = "detail"
            libraryScreen.open("shows", appGrid)
        } else if (selfTest === "iptv" || selfTest === "iptvplay" || selfTest === "iptvsources") {
            // Test: openbare lijst met vrij beschikbare Nederlandse zenders (iptv-org)
            if (iptv.sources.length === 0) {
                iptv.addSource("m3u-url", "Test", "https://iptv-org.github.io/iptv/countries/nl.m3u", "", "")
            }
            iptvScreen.autoPlay = selfTest === "iptvplay"
            iptvScreen.open(appGrid)
            if (selfTest === "iptvsources") {
                iptvScreen.openSources()
            }
        } else if (selfTest === "librarysetup") {
            libraryScreen.open("movies", appGrid)
            libraryScreen.openSetup()
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
        // Links en onder donkerder, zodat tekst en tegels leesbaar blijven
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#d00b0c0f" }
                GradientStop { position: 0.6; color: "#500b0c0f" }
                GradientStop { position: 1.0; color: "#200b0c0f" }
            }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#000b0c0f" }
                GradientStop { position: 0.45; color: "#600b0c0f" }
                GradientStop { position: 1.0; color: "#e80b0c0f" }
            }
        }
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

    // --- Bovenbalk: naam links, snelknoppen in het midden, klok rechts ---
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.unit * 3
        height: root.unit * 6

        Text {
            id: brand
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: "white"
            font.pixelSize: root.unit * 3.2
            font.weight: Font.DemiBold
            text: "Bigscreen"
        }

        Text {
            id: clock
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: "white"
            font.pixelSize: root.unit * 3.2
        }
        Text {
            id: dateLabel
            anchors.right: clock.left
            anchors.rightMargin: root.unit * 2
            anchors.baseline: clock.baseline
            color: "#b0b4bb"
            font.pixelSize: root.unit * 2
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

    // --- Snelknoppen in de bovenbalk ---
    ListView {
        id: quickRow
        anchors.verticalCenter: header.verticalCenter
        anchors.left: header.left
        anchors.leftMargin: brand.width + root.unit * 4
        width: Math.min(root.unit * 19 * quickModel.count,
                        header.width - brand.width - clock.width - dateLabel.width - root.unit * 10)
        height: root.unit * 5.6
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
            compact: width < root.unit * 16
            selected: quickRow.activeFocus && quickRow.currentIndex === index
            onActivated: { quickRow.currentIndex = index; quickRow.trigger(index) }
            onHovered: { if (!menu.visible && !addOverlay.visible) { quickRow.currentIndex = index; quickRow.forceActiveFocus() } }
        }

        Keys.onReturnPressed: trigger(currentIndex)
        Keys.onEnterPressed: trigger(currentIndex)
        Keys.onDownPressed: (webModel.count > 0 ? streamGrid : appGrid).forceActiveFocus()
    }

    // --- Groot tekstvlak: wat heeft nu focus ---
    Item {
        id: hero
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.unit * 4
        anchors.rightMargin: root.unit * 4
        height: root.heroShown ? root.unit * 21 : 0
        opacity: root.heroShown ? 1 : 0
        clip: true
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Image {
            id: heroIcon
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.unit * 2.5
            width: root.focusIcon !== "" ? root.unit * 13 : 0
            height: root.unit * 13
            sourceSize: Qt.size(256, 256)
            source: root.focusIcon
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        Column {
            anchors.left: heroIcon.right
            anchors.leftMargin: heroIcon.width > 0 ? root.unit * 3 : 0
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.unit * 2.5
            width: parent.width * 0.7
            spacing: root.unit

            Text {
                width: parent.width
                color: "white"
                font.pixelSize: root.unit * 7.5
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                text: root.focusName
            }
            Text {
                color: "#c4c7cc"
                font.pixelSize: root.unit * 2.4
                text: root.focusKind
            }
        }
    }

    // --- Streaming: tabbladen Video, Muziek, Luisterboeken, Podcasts ---
    ListView {
        id: streamTitle
        anchors.top: hero.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.unit * 1.5
        anchors.leftMargin: root.unit * 3
        height: root.unit * 4.6
        orientation: ListView.Horizontal
        spacing: root.unit
        interactive: false
        keyNavigationEnabled: true
        currentIndex: model.findIndex(t => t.key === webModel.category)
        model: [
            { key: "video", label: "Video" },
            { key: "muziek", label: "Muziek" },
            { key: "luisterboeken", label: "Luisterboeken" },
            { key: "podcasts", label: "Podcasts" }
        ]

        delegate: Rectangle {
            id: tab
            required property int index
            required property var modelData
            readonly property bool chosen: webModel.category === modelData.key
            readonly property bool focused: streamTitle.activeFocus && streamTitle.currentIndex === index
            width: tabLabel.implicitWidth + root.unit * 4
            height: streamTitle.height
            radius: height / 2
            color: focused ? "#e8eaed" : chosen ? "#40ffffff" : "transparent"
            Text {
                id: tabLabel
                anchors.centerIn: parent
                color: tab.focused ? "#111318" : tab.chosen ? "white" : "#c4c7cc"
                font.pixelSize: root.unit * 2.4
                font.weight: tab.chosen ? Font.DemiBold : Font.Normal
                text: tab.modelData.label
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    webModel.category = tab.modelData.key
                    streamGrid.currentIndex = 0
                    streamGrid.forceActiveFocus()
                }
            }
        }

        // Links/rechts wisselt meteen van tabblad
        onCurrentIndexChanged: {
            if (activeFocus && currentIndex >= 0) {
                webModel.category = model[currentIndex].key
            }
        }
        Keys.onUpPressed: quickRow.forceActiveFocus()
        Keys.onDownPressed: {
            streamGrid.currentIndex = 0
            streamGrid.forceActiveFocus()
        }
        Keys.onReturnPressed: {
            streamGrid.currentIndex = 0
            streamGrid.forceActiveFocus()
        }
    }

    GridView {
        id: streamGrid
        // Marge rondom, zodat de vergrote gekozen tegel niet wordt afgesneden
        readonly property real pad: root.unit * 2.2
        anchors.top: streamTitle.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.unit * 1.5
        anchors.rightMargin: root.unit * 1.5
        visible: webModel.count > 0
        leftMargin: pad
        rightMargin: pad
        topMargin: pad * 0.6
        bottomMargin: pad * 0.6
        cellWidth: Math.floor((width - pad * 2) / root.columns)
        cellHeight: cellWidth * 0.46
        // Vult de ruimte tussen het tekstvlak en de rij Media
        anchors.bottom: sectionTitle.top
        anchors.bottomMargin: root.unit * 0.5
        focus: webModel.count > 0
        model: webModel
        keyNavigationEnabled: true
        clip: true
        highlightMoveDuration: 150

        function trigger(index) {
            if (index < 0) {
                return
            }
            const name = webModel.nameAt(index)
            root.showToast(webModel.launch(index) ? name + " openen… (sluiten met Alt+F4)" : name + " kon niet geopend worden")
        }

        delegate: BannerTile {
            width: streamGrid.cellWidth
            height: streamGrid.cellHeight
            selected: streamGrid.activeFocus && streamGrid.currentIndex === index
            onActivated: { streamGrid.currentIndex = index; streamGrid.trigger(index) }
            onHovered: { if (!menu.visible && !addOverlay.visible) { streamGrid.currentIndex = index; streamGrid.forceActiveFocus() } }
            onMenuRequested: { streamGrid.currentIndex = index; root.openTileMenu(webModel, index, streamGrid) }
            // Slepen: de tegel neemt de plek in van de tegel waar de muis boven hangt
            onDragMoved: (x, y) => {
                const pos = mapToItem(streamGrid.contentItem, x, y)
                const to = streamGrid.indexAt(pos.x, pos.y)
                if (to >= 0 && to !== index) {
                    webModel.move(index, to)
                    streamGrid.currentIndex = to
                }
            }
        }

        move: Transition { NumberAnimation { properties: "x,y"; duration: 160; easing.type: Easing.OutCubic } }
        displaced: Transition { NumberAnimation { properties: "x,y"; duration: 160; easing.type: Easing.OutCubic } }

        Keys.onReturnPressed: trigger(currentIndex)
        Keys.onEnterPressed: trigger(currentIndex)
        Keys.onMenuPressed: root.openTileMenu(webModel, currentIndex, streamGrid)
        Keys.onUpPressed: (event) => {
            if (currentIndex < root.columns) {
                streamTitle.forceActiveFocus()
            } else {
                event.accepted = false
            }
        }
        Keys.onDownPressed: (event) => {
            if (currentIndex + root.columns >= count) {
                appGrid.forceActiveFocus()
            } else {
                event.accepted = false
            }
        }
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_F2) {
                root.openTileMenu(webModel, currentIndex, streamGrid)
                event.accepted = true
            }
        }
    }

    // --- Raster met toepassingen ---
    Text {
        id: sectionTitle
        anchors.bottom: appGrid.top
        anchors.left: parent.left
        anchors.topMargin: root.unit * 1.5
        anchors.leftMargin: root.unit * 4
        color: "white"
        font.pixelSize: root.unit * 2.6
        font.weight: Font.DemiBold
        text: "Media"
    }

    GridView {
        id: appGrid
        // Een rij onderaan: mappen Muziek/Video's/Afbeeldingen, MPC-HC en eigen programma's
        height: cellHeight + pad * 1.2
        anchors.bottom: hint.top
        anchors.left: parent.left
        anchors.right: parent.right
        readonly property real pad: root.unit * 2.2
        anchors.leftMargin: root.unit * 1.5
        anchors.rightMargin: root.unit * 1.5
        anchors.bottomMargin: root.unit * 0.5
        leftMargin: pad
        rightMargin: pad
        topMargin: pad * 0.6
        bottomMargin: pad * 0.6
        cellWidth: Math.floor((width - pad * 2) / root.columns)
        cellHeight: cellWidth * 0.46
        model: appModel
        focus: webModel.count === 0
        clip: true
        keyNavigationEnabled: true
        highlightMoveDuration: 150
        // Ruimte houden zodat de geselecteerde tegel niet tegen de rand plakt

        function trigger(index) {
            if (index < 0) {
                return
            }
            const name = appModel.nameAt(index)
            root.showToast(appModel.launch(index) ? name + " openen…" : name + " is niet gevonden op deze pc")
        }

        delegate: BannerTile {
            width: appGrid.cellWidth
            height: appGrid.cellHeight
            selected: appGrid.activeFocus && appGrid.currentIndex === index
            onActivated: { appGrid.currentIndex = index; appGrid.trigger(index) }
            onHovered: { if (!menu.visible && !addOverlay.visible) { appGrid.currentIndex = index; appGrid.forceActiveFocus() } }
            onMenuRequested: { appGrid.currentIndex = index; root.openTileMenu(appModel, index, appGrid) }
            // Slepen: de tegel neemt de plek in van de tegel waar de muis boven hangt
            onDragMoved: (x, y) => {
                const pos = mapToItem(appGrid.contentItem, x, y)
                const to = appGrid.indexAt(pos.x, pos.y)
                if (to >= 0 && to !== index) {
                    appModel.move(index, to)
                    appGrid.currentIndex = to
                }
            }
        }

        move: Transition { NumberAnimation { properties: "x,y"; duration: 160; easing.type: Easing.OutCubic } }
        displaced: Transition { NumberAnimation { properties: "x,y"; duration: 160; easing.type: Easing.OutCubic } }

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
                (webModel.count > 0 ? streamGrid : quickRow).forceActiveFocus()
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
        text: ""
    }

    Text {
        id: hint
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: root.unit * 1.5
        color: "#7d8188"
        font.pixelSize: root.unit * 2
        text: (gamepad.connectedCount > 0 ? "Controller verbonden  ·  " : "")
              + "Pijltjes / D-pad: navigeren  ·  Enter / A: openen  ·  F2, rechtermuisknop of X: aanpassen  ·  Ingedrukt houden en slepen: verplaatsen"
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

    PlacesPicker {
        id: placesPicker
        property var model: null
        property int row: -1
        property string direction: ""
        onAccepted: (places) => root.moveTile(model, row, direction, places)
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

    // Live tv: zenderlijst en speler
    IptvScreen {
        id: iptvScreen
    }

    // Films en Series: eigen scherm met de bibliotheek
    LibraryScreen {
        id: libraryScreen
    }

    Connections {
        target: appModel
        function onInternalRequested(target) {
            if (target === "bigscreen:iptv") {
                iptvScreen.open(appGrid)
            } else {
                libraryScreen.open(target === "bigscreen:shows" ? "shows" : "movies", appGrid)
            }
        }
    }
}
