// Startpagina van Bigscreen voor Windows: klok, snelknoppen en rijen onder elkaar
// (Video, Muziek, Podcasts, Media) die meescrollen. Volledig te bedienen met
// pijltjestoetsen, Enter en een gamepad.
// Eigen QtQuick-versie van containments/homescreen (die aan Plasma vastzit).
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Dialogs

Rectangle {
    id: root

    readonly property real unit: height / 100
    readonly property int columns: unit > 0 ? Math.max(4, Math.floor(width / (unit * 25))) : 5

    // Model en rij van de tegel waarvoor het aanpas-menu of de bestandskiezer open staat
    property var editModel: appModel
    property int editRow: -1

    color: "#0b0c0f"

    // De rijen op de startpagina, van boven naar beneden
    readonly property var sectionDefs: (resume.count > 0 ? [{ title: "Verder kijken", model: resume }] : []).concat([
        { title: "Video", model: webVideo },
        { title: "Muziek", model: webMusic },
        { title: "Podcasts", model: webPodcasts },
        { title: "Media", model: appModel }
    ])
    readonly property var webModels: [webVideo, webMusic, webPodcasts]
    // Rij "Verder kijken" verschijnt of verdwijnt: de rijen worden opnieuw gemaakt, focus terugzetten
    onSectionDefsChanged: Qt.callLater(() => {
        if (!frameScreen.visible && !iptvScreen.visible && !libraryScreen.visible && root.currentSection === null) {
            focusSection(0, 0, false)
        }
    })

    // Rij en tegel die nu focus hebben
    property Item currentSection: null
    readonly property var focusModel: currentSection !== null && currentSection.grid.activeFocus ? currentSection.model : null
    readonly property int focusRow: focusModel ? currentSection.grid.currentIndex : -1
    readonly property bool focusIsWeb: focusModel ? focusModel !== appModel : false

    // Muis telt alleen als hij echt bewogen is, niet als tegels onder een stilstaande
    // cursor doorschuiven tijdens het scrollen met pijltjes of controller
    property double lastMouseMove: 0
    function mouseActive() {
        // Muis boven een volledig scherm (schilderij, live tv, bibliotheek): de tegels
        // eronder mogen dan geen focus pakken, anders werken Esc/B niet meer
        if (frameScreen.visible || iptvScreen.visible || libraryScreen.visible) {
            return false
        }
        return Date.now() - lastMouseMove < 400
    }

    // Naam en soort van de tegel die nu focus heeft (voor het grote tekstvlak bovenaan)
    readonly property string focusName: focusModel ? focusModel.nameAt(focusRow)
                                       : quickRow.activeFocus ? quickModel.get(quickRow.currentIndex).label : ""
    readonly property string focusKind: focusModel ? currentSection.title + "  ·  Enter om te openen"
                                       : quickRow.activeFocus ? "Instellingen" : ""
    // (revision in de binding: opnieuw opvragen zodra een logo binnen is of wijzigt)
    readonly property string focusIconRaw: focusModel ? (focusModel.revision, focusModel.iconAt(focusRow)) : ""
    // Pictogrammen uit het lettertype (Films, Series) niet als afbeelding laden
    readonly property string focusIcon: focusIconRaw.startsWith("glyph:") ? "" : focusIconRaw
    // Achtergrondkleur: de kleur van het logo van de dienst met focus
    readonly property color accent: focusIsWeb && focusRow >= 0 ? (focusModel.revision, focusModel.accentAt(focusRow)) : "#1d3557"

    MouseArea {
        anchors.fill: parent
        z: 1000
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        onPositionChanged: root.lastMouseMove = Date.now()
    }
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

    function sectionFor(model) {
        for (let i = 0; i < sections.count; ++i) {
            const item = sections.itemAt(i)
            if (item && item.model === model) {
                return item
            }
        }
        return null
    }

    function mediaGrid() {
        const media = sectionFor(appModel)
        return media ? media.grid : quickRow
    }

    // Focus naar rij i; lege (verborgen) rijen worden overgeslagen
    function focusSection(i, column, fromBelow) {
        while (i >= 0 && i < sections.count) {
            const item = sections.itemAt(i)
            if (item && item.enter(column, fromBelow)) {
                return
            }
            i += fromBelow ? -1 : 1
        }
        if (i < 0) {
            quickRow.forceActiveFocus()
            page.contentY = 0
        }
    }

    // Pagina zo scrollen dat de gekozen tegel (en bij de eerste rij de titel) in beeld is
    function scrollTo(section) {
        const g = section.grid
        const row = Math.floor(Math.max(0, g.currentIndex) / root.columns)
        const top = row === 0 ? section.y : section.y + g.y + g.topMargin + row * g.cellHeight - root.unit * 2
        const bottom = section.y + g.y + g.topMargin + (row + 1) * g.cellHeight + root.unit * 2
        if (top < page.contentY) {
            page.contentY = Math.max(0, top)
        } else if (bottom > page.contentY + page.height) {
            page.contentY = Math.max(0, Math.min(page.contentHeight - page.height, bottom - page.height))
        }
    }

    function launch(model, row) {
        if (row < 0) {
            return
        }
        const name = model.nameAt(row)
        showToast(model.launch(row) ? name + " openen…" : name + " kon niet geopend worden")
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
        if (model === resume) {
            menu.open(model.nameAt(row), [
                { label: "Verder kijken", action: "resume-play" },
                { label: "Uit deze rij halen", action: "resume-remove" },
                { label: "Annuleren", action: "" }
            ], focusItem)
            return
        }
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
        const section = sectionFor(model)
        if (section) {
            section.grid.currentIndex = to
            section.grid.forceActiveFocus()
        }
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
        let hidden = appModel.hiddenCount
        for (const m of webModels) {
            hidden += m.hiddenCount
        }
        if (hidden > 0) {
            entries.push({ label: "Verwijderde tegels terugzetten (" + hidden + ")", action: "unhide" })
        }
        entries.push({ label: "Sluiten", action: "" })
        menu.open("Aanpassen", entries, quickRow)
    }

    function handleMenuAction(action) {
        if (action === "resume-play") {
            launch(resume, editRow)
        } else if (action === "resume-remove") {
            resume.remove(editRow)
        } else if (action === "icon") {
            imageDialog.purpose = "icon"
            imageDialog.title = "Pictogram kiezen voor " + editModel.nameAt(editRow)
            imageDialog.open()
        } else if (action === "icon-reset") {
            editModel.clearCustomIcon(editRow)
        } else if (action.startsWith("move-")) {
            const dir = action.substring(5)
            const section = sectionFor(editModel)
            const grid = section ? section.grid : quickRow
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
            for (const m of webModels) {
                m.restoreHidden()
            }
            showToast("Alle tegels staan weer op de startpagina")
        }
    }

    function addTile(name, target) {
        // Een pad naar een bestand is een programma; al het andere een webadres
        const isFile = /^[a-zA-Z]:[\\/]/.test(target.trim()) || target.trim().startsWith("\\\\")
                       || target.trim().startsWith("\"") || target.trim().startsWith("file:")
        // Website: in de rij waar je het laatst was (Muziek, Podcasts, ...), anders bij Video
        const webTarget = currentSection && currentSection.model !== appModel ? currentSection.model : webVideo
        const ok = isFile ? appModel.addTile(name, target) : webTarget.addTile(name, target)
        if (!ok) {
            showToast("Toevoegen mislukt: controleer het adres of pad (of de tegel bestaat al)")
        } else {
            showToast("Tegel toegevoegd")
        }
    }

    Component.onCompleted: {
        focusSection(0, 0, false)
        if (selfTest === "addtile") {
            addOverlay.open(quickRow)
        } else if (selfTest === "podcasts") {
            Qt.callLater(() => focusSection(sectionDefs.findIndex(d => d.model === webPodcasts), 1, false))
        } else if (selfTest === "moveask") {
            focusSection(0, 2, false)
            editModel = webVideo
            editRow = 2
            Qt.callLater(() => handleMenuAction("move-down"))
        } else if (selfTest === "library") {
            libraryScreen.open("shows", mediaGrid())
        } else if (selfTest === "librarymovies") {
            libraryScreen.open("movies", mediaGrid())
        } else if (selfTest === "librarydetail") {
            libraryScreen.autoOpen = "detail"
            libraryScreen.open("shows", mediaGrid())
        } else if (selfTest === "iptv" || selfTest === "iptvplay" || selfTest === "iptvsources") {
            // Test: openbare lijst met vrij beschikbare Nederlandse zenders (iptv-org)
            if (iptv.sources.length === 0) {
                iptv.addSource("m3u-url", "Test", "https://iptv-org.github.io/iptv/countries/nl.m3u", "", "")
            }
            iptvScreen.autoPlay = selfTest === "iptvplay"
            iptvScreen.open(mediaGrid())
            if (selfTest === "iptvsources") {
                iptvScreen.openSources()
            }
        } else if (selfTest === "iptvbar" || selfTest === "iptvepg") {
            // Test: eigen lijst met gids (aangemaakt door de CI)
            if (iptv.sources.length === 0) {
                iptv.addSource("m3u-file", "Gids-test", selfTestM3u, "", "")
            }
            iptvScreen.autoPlay = true
            iptvScreen.pinInfo = selfTest === "iptvbar"
            iptvScreen.autoGuide = selfTest === "iptvepg"
            iptvScreen.open(mediaGrid())
        } else if (selfTest.startsWith("frame")) {
            // Test: frame-chicago, frame-met, frame-nature, frame-mix, frame-lijst, frame-settings
            const kinds = { "frame-chicago": 0, "frame-met": 1, "frame-nature": 2, "frame-mix": 4, "frame-lijst": 0, "frame-settings": 2, "frame-esc": 2, "frame-mouseesc": 0 }
            frame.source = kinds[selfTest] !== undefined ? kinds[selfTest] : 0
            frame.fill = selfTest !== "frame-lijst"
            frame.interval = 5
            frameScreen.open(mediaGrid())
            if (selfTest === "frame-settings") {
                frameScreen.openSettings()
            }
        } else if (selfTest === "record" || selfTest === "recordpanel") {
            // Test: zender uit de testlijst 20 seconden opnemen naar een testmap
            if (iptv.sources.length === 0) {
                iptv.addSource("m3u-file", "Gids-test", selfTestM3u, "", "")
            }
            recorder.folder = selfTestRecordDir
            iptvScreen.autoPlay = true
            iptvScreen.autoRecord = selfTest
            iptvScreen.open(mediaGrid())
        } else if (selfTest === "iptvfreeguide") {
            // Test: gratis zenders met de echte nachtelijke gids; NPO 1 met de balk vast in beeld
            iptv.addFreeSources()
            iptv.group = "Alle zenders"
            iptv.search = "NPO 1"
            iptvScreen.autoPlay = true
            iptvScreen.pinInfo = true
            iptvScreen.open(mediaGrid())
        } else if (selfTest === "iptvfree") {
            iptvScreen.open(mediaGrid())
        } else if (selfTest.startsWith("m-")) {
            // Schermafbeeldingen voor de handleiding
            if (iptv.sources.length === 0) {
                iptv.addSource("m3u-file", "Nederlandse zenders", selfTestM3u, "", "")
            }
            if (selfTest === "m-home") {
                const media = sectionDefs.findIndex(d => d.model === appModel)
                focusSection(media, 2, false)
                return
            }
            iptvScreen.demo = selfTest
            iptvScreen.autoPlay = selfTest === "m-bar" || selfTest.startsWith("m-guide") && selfTest !== "m-guidelist"
            iptvScreen.pinInfo = selfTest === "m-bar"
            iptvScreen.autoGuide = selfTest === "m-guide" || selfTest === "m-guide2"
            iptvScreen.guideStart = selfTest === "m-guide2" ? 3 : 0
            iptvScreen.open(mediaGrid())
        } else if (selfTest === "resume") {
            // Test: startscherm met de rij Verder kijken (geschiedenis door de test klaargezet)
        } else if (selfTest === "epgrecord") {
            // Test: in de gids het programma van nu en een later programma laten opnemen
            if (iptv.sources.length === 0) {
                iptv.addSource("m3u-file", "Gids-test", selfTestM3u, "", "")
            }
            recorder.folder = selfTestRecordDir
            iptvScreen.autoPlay = true
            iptvScreen.autoGuide = true
            iptvScreen.autoGuideRecord = true
            iptvScreen.guideStart = 3
            iptvScreen.open(mediaGrid())
        } else if (selfTest === "mpcplay") {
            // Test: eerste serie openen en vanaf de eerste aflevering afspelen in MPC-HC
            libraryScreen.autoOpen = "play"
            libraryScreen.open("shows", mediaGrid())
        } else if (selfTest === "librarysetup") {
            libraryScreen.open("movies", mediaGrid())
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

        Image {
            id: brandIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: root.unit * 4.4
            height: width
            source: "qrc:/assets/kijkluister-256.png"
            sourceSize: Qt.size(128, 128)
            smooth: true
        }
        Text {
            id: brand
            anchors.left: brandIcon.right
            anchors.leftMargin: root.unit * 1.2
            anchors.verticalCenter: parent.verticalCenter
            color: "white"
            font.pixelSize: root.unit * 3.2
            font.weight: Font.DemiBold
            text: "Kijkluister"
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
        anchors.leftMargin: brand.x + brand.width + root.unit * 3
        width: Math.min(root.unit * 19 * quickModel.count,
                        header.width - brand.x - brand.width - clock.width - dateLabel.width - root.unit * 10)
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
            onHovered: { if (!menu.visible && !addOverlay.visible && root.mouseActive()) { quickRow.currentIndex = index; quickRow.forceActiveFocus() } }
        }

        Keys.onReturnPressed: trigger(currentIndex)
        Keys.onEnterPressed: trigger(currentIndex)
        Keys.onDownPressed: root.focusSection(0, 0, false)
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

    // --- Rijen onder elkaar: Video, Muziek, Podcasts, Media (scrollt) ---
    Flickable {
        id: page
        anchors.top: hero.bottom
        anchors.bottom: hint.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.unit
        anchors.leftMargin: root.unit * 1.5
        anchors.rightMargin: root.unit * 1.5
        contentWidth: width
        contentHeight: sectionColumn.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // Na een maatwijziging (start, ander scherm) de gekozen tegel weer in beeld brengen
        onHeightChanged: if (root.currentSection) root.scrollTo(root.currentSection)
        onContentHeightChanged: if (root.currentSection) root.scrollTo(root.currentSection)
        Behavior on contentY { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Column {
            id: sectionColumn
            width: page.width
            spacing: root.unit * 0.5

            Repeater {
                id: sections
                model: root.sectionDefs
                delegate: SectionGrid {
                    id: sectionItem
                    required property int index
                    required property var modelData
                    width: sectionColumn.width
                    title: modelData.title
                    model: modelData.model
                    columns: root.columns
                    unit: root.unit
                    canHover: () => !menu.visible && !addOverlay.visible && !placesPicker.visible && root.mouseActive()
                    onExitUp: (column) => root.focusSection(index - 1, column, true)
                    onExitDown: (column) => root.focusSection(index + 1, column, false)
                    onLaunchRequested: (row) => root.launch(sectionItem.model, row)
                    onMenuRequested: (row) => root.openTileMenu(sectionItem.model, row, sectionItem.grid)
                    onTileFocused: {
                        root.currentSection = sectionItem
                        root.scrollTo(sectionItem)
                    }
                }
            }
        }
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

    // Schilderij: kunst of natuurfoto's
    FrameScreen {
        id: frameScreen
    }

    // Melding als Kijkluister MPC-HC of ffmpeg ophaalt (op de achtergrond)
    Rectangle {
        z: 950
        visible: components.status !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.height * 0.04
        width: toastRow.implicitWidth + root.height * 0.05
        height: root.height * 0.06
        radius: height / 2
        color: "#e6202124"
        border.color: "#33ffffff"
        Row {
            id: toastRow
            anchors.centerIn: parent
            spacing: root.height * 0.015
            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: "white"
                font.pixelSize: root.height * 0.024
                text: components.status
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: components.progress >= 0
                width: root.height * 0.18
                height: root.height * 0.008
                radius: height / 2
                color: "#40ffffff"
                Rectangle {
                    width: parent.width * Math.max(0, components.progress) / 100
                    height: parent.height
                    radius: height / 2
                    color: "#ffb74d"
                }
            }
        }
    }

    // Films en Series: eigen scherm met de bibliotheek
    LibraryScreen {
        id: libraryScreen
    }

    Connections {
        target: appModel
        function onInternalRequested(target) {
            if (target === "bigscreen:iptv") {
                iptvScreen.open(mediaGrid())
            } else if (target === "bigscreen:frame") {
                frameScreen.open(mediaGrid())
            } else {
                libraryScreen.open(target === "bigscreen:shows" ? "shows" : "movies", mediaGrid())
            }
        }
    }
}
