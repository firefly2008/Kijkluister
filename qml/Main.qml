// Startpagina van Bigscreen voor Windows: klok, snelknoppen en rijen onder elkaar
// (Video, Muziek, Podcasts, Media) die meescrollen. Volledig te bedienen met
// pijltjestoetsen, Enter en een gamepad.
// Eigen QtQuick-versie van containments/homescreen (die aan Plasma vastzit).
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Dialogs
import QtQuick.Effects

Rectangle {
    id: root

    readonly property real unit: height / 100
    readonly property int columns: unit > 0 ? Math.max(4, Math.floor(width / (unit * 25))) : 5

    // Model en rij van de tegel waarvoor het aanpas-menu of de bestandskiezer open staat
    property var editModel: appModel
    property int editRow: -1

    color: "#0b0c0f"

    // Typen op het startscherm: meteen zoeken
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_HomePage) {
            goHomeScreen()
            event.accepted = true
            return
        }
        const overlayOpen = iptvScreen.visible || libraryScreen.visible || frameScreen.visible || radioPlayer.visible || menu.visible
                            || picker.visible || welcomeOverlay.visible || addOverlay.visible || pinPad.visible || placesPicker.visible
                            || resumeScreen.visible || releaseInfo.visible || helpOverlay.visible
        // Cijfers 1-9: tegel 1-9 van de bovenste rij openen
        if (!overlayOpen && event.text.length === 1 && /[1-9]/.test(event.text) && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
            const top = sectionDefs.length > 0 ? sectionDefs[0].model : null
            const n = parseInt(event.text) - 1
            if (top && n < top.count) {
                console.info("Number key", event.text, top.nameAt(n))
                launch(top, n)
            }
            event.accepted = true
            return
        }
        if (!overlayOpen && event.text.length === 1 && /[a-zA-Z0]/.test(event.text) && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
            root.openPicker("all", "Zoeken", root.currentSection ? root.currentSection.grid : quickRow, event.text)
            event.accepted = true
        }
    }

    // De rijen op de startpagina, van boven naar beneden
    // Rijen in de volgorde die je zelf kiest (Menu op een tegel: Rij omhoog/omlaag).
    // Standaard staat Verder kijken onder Media.
    readonly property var allSectionDefs: [
        { title: "Vaak gebruikt", model: usage },
        { title: "Video", model: webVideo },
        { title: "Muziek", model: webMusic },
        { title: "Radio", model: radio },
        { title: "Podcasts", model: webPodcasts },
        { title: "Nieuws", model: webNews },
        { title: "Media", model: appModel }
    ]
    readonly property var sectionDefs: {
        const order = appModel.sectionOrder
        // (In de rooktests alleen bij de test "usage", zodat de rijvolgorde van andere tests klopt)
        const defs = allSectionDefs.filter(d => d.model === usage ? usage.count >= 3 && (selfTest === "" || selfTest === "usage") : d.model.count > 0)
        const rank = (d) => { const i = order.indexOf(d.title); return i >= 0 ? i : 100 + allSectionDefs.indexOf(d) }
        return defs.slice().sort((a, b) => rank(a) - rank(b))
    }
    function moveSection(model, step) {
        const titles = allSectionDefs.slice().sort((a, b) => {
            const order = appModel.sectionOrder
            const ra = order.indexOf(a.title) >= 0 ? order.indexOf(a.title) : 100 + allSectionDefs.indexOf(a)
            const rb = order.indexOf(b.title) >= 0 ? order.indexOf(b.title) : 100 + allSectionDefs.indexOf(b)
            return ra - rb
        }).map(d => d.title)
        const title = allSectionDefs.find(d => d.model === model).title
        // Over verborgen rijen (lege Verder kijken) heen springen
        const visible = sectionDefs.map(d => d.title)
        const vi = visible.indexOf(title)
        const target = visible[vi + step]
        if (target === undefined) return
        titles.splice(titles.indexOf(title), 1)
        titles.splice(titles.indexOf(target) + (step > 0 ? 1 : 0), 0, title)
        appModel.sectionOrder = titles
        showToast("Rij " + title + (step < 0 ? " staat nu hoger" : " staat nu lager"))
        Qt.callLater(() => { const sec = sectionFor(model); if (sec) sec.grid.forceActiveFocus() })
    }
    // Categorie van een rij (voor Vaak gebruikt en inklappen)
    function categoryOf(model) {
        return model === appModel ? "media" : model === webVideo ? "video" : model === webMusic ? "muziek"
             : model === webPodcasts ? "podcasts" : model === webNews ? "nieuws" : model === radio ? "radio" : ""
    }
    // Rij ingeklapt? Zelf ingeklapt, of (automatisch) twee weken niet gebruikt
    property int settingsRevision: 0
    Connections { target: appModel; function onSettingsChanged() { root.settingsRevision++ } }
    function isCollapsed(title, model) {
        settingsRevision
        const manual = appModel.setting("collapsed", [])
        const expanded = appModel.setting("expanded", [])
        if (manual.indexOf(title) >= 0) return true
        if (expanded.indexOf(title) >= 0 || model === usage || model === appModel) return false
        return appModel.setting("autoCollapse", true) && usage.daysUnused(categoryOf(model)) > 14
    }
    function toggleCollapsed(model) {
        const title = allSectionDefs.find(d => d.model === model).title
        const now = isCollapsed(title, model)
        let manual = appModel.setting("collapsed", []).filter(t => t !== title)
        let expanded = appModel.setting("expanded", []).filter(t => t !== title)
        if (now) expanded.push(title); else manual.push(title)
        appModel.setSetting("collapsed", manual)
        appModel.setSetting("expanded", expanded)
        showToast(now ? "Rij " + title + " staat weer open" : "Rij " + title + " is ingeklapt (kies hem om te openen)")
    }
    function sectionMoveEntries(model) {
        const visible = sectionDefs.map(d => d.model)
        const i = visible.indexOf(model)
        const entries = []
        if (i > 0) entries.push({ label: "Rij omhoog verplaatsen", action: "section-up" })
        if (i >= 0 && i < visible.length - 1) entries.push({ label: "Rij omlaag verplaatsen", action: "section-down" })
        const def = allSectionDefs.find(d => d.model === model)
        if (def && model !== usage) entries.push({ label: isCollapsed(def.title, model) ? "Rij uitklappen" : "Rij inklappen", action: "section-collapse" })
        return entries
    }
    readonly property var webModels: [webVideo, webMusic, webPodcasts, webNews]
    // Rij "Verder kijken" verschijnt of verdwijnt: de rijen worden opnieuw gemaakt, focus terugzetten
    onSectionDefsChanged: Qt.callLater(() => {
        if (!frameScreen.visible && !iptvScreen.visible && !libraryScreen.visible && !radioPlayer.visible && root.currentSection === null
                && !quickRow.activeFocus && !menu.visible && !welcomeOverlay.visible && !addOverlay.visible) {
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
        if (frameScreen.visible || iptvScreen.visible || libraryScreen.visible || radioPlayer.visible) {
            return false
        }
        return Date.now() - lastMouseMove < 400
    }

    // Naam en soort van de tegel die nu focus heeft (voor het grote tekstvlak bovenaan)
    readonly property string focusName: focusModel ? focusModel.nameAt(focusRow)
                                       : quickRow.activeFocus ? quickModel.get(quickRow.currentIndex).label : ""
    readonly property string focusKind: focusModel ? currentSection.title
                                       : quickRow.activeFocus ? quickModel.get(quickRow.currentIndex).about : ""
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
        // Meebewegende achtergrond: het logo van de gekozen tegel, groot en wazig (zoals Apple TV)
        Image {
            id: ambientIcon
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: -parent.width * 0.05
            width: parent.width * 0.55
            height: width
            source: root.focusIcon
            fillMode: Image.PreserveAspectFit
            sourceSize: Qt.size(256, 256)
            asynchronous: true
            visible: false
        }
        // Eén keer vervagen en als plaatje bewaren (layer): anders rekent de vervaging bij elk videobeeld mee.
        // Verborgen zolang een volledig scherm (tv, bibliotheek, schilderij, radio) open is.
        Item {
            anchors.fill: ambientIcon
            visible: !(iptvScreen.visible || libraryScreen.visible || frameScreen.visible || radioPlayer.visible)
            layer.enabled: visible
            opacity: root.focusIcon !== "" ? 0.28 : 0
            Behavior on opacity { NumberAnimation { duration: 450 } }
            MultiEffect {
                anchors.fill: parent
                source: ambientIcon
                blurEnabled: true
                blur: 1.0
                blurMax: 32
            }
        }
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

    function launch(model, row, pinOk) {
        if (row < 0) {
            return
        }
        // Vaak gebruikt: de echte tegel in zijn eigen rij openen
        if (model === usage) {
            const cat = usage.categoryAt(row)
            const src = usage.sourceModel(cat)
            const r = usage.sourceRow(cat, usage.pathAt(row))
            if (src && r >= 0) launch(src, r, pinOk)
            return
        }
        if (model === radio) {
            if (radio.isAddTile(row)) {
                openRadioSearch()
                return
            }
            // Radio speelt in Kijkluister zelf
            usage.record("radio", radio.pathAt(row))
            const section = sectionFor(radio)
            radioPlayer.open(row, section ? section.grid : mediaGrid())
            return
        }
        const path = model.pathAt ? model.pathAt(row) : ""
        const name = model.nameAt(row)
        // Kinderslot: eerst de pincode
        if (!pinOk && parental.needsPin(path)) {
            pinPad.ask(name + " is vergrendeld", "Vul de pincode van het kinderslot in.",
                       (pin) => { if (!parental.check(pin)) return false; root.launch(model, row, true); return true },
                       currentSection ? currentSection.grid : quickRow)
            return
        }
        // Een andere app of film: radio stoppen (bij het schilderij mag hij doorspelen)
        if (radioPlayer.row >= 0 && path !== "bigscreen:frame") {
            radioPlayer.stopPlayback()
        }
        if (path !== "bigscreen:radio-now" && path !== "bigscreen:resume" && categoryOf(model) !== "") {
            usage.record(categoryOf(model), path)
        }
        if (model.launch(row)) {
            // App of website voorop: Home-knop en Home-toets brengen je terug
            if (!path.startsWith("bigscreen:")) homeBridge.externalLaunched()
            // Blijft staan tot het venster echt open is (Kijkluister gaat dan naar de achtergrond)
            showToast(name + " wordt geopend…", 12000)
            launchSlowTimer.name = name
            launchSlowTimer.restart()
        } else {
            showToast(name + " kon niet worden geopend. Probeer het opnieuw.", 5000)
        }
    }

    function showToast(message, ms) {
        toast.text = message
        toastTimer.interval = ms || 3500
        toastTimer.restart()
    }

    // Duurt het openen lang en staat Kijkluister nog steeds voorop: een uitweg bieden
    Timer {
        id: launchSlowTimer
        property string name
        interval: 10000
        onTriggered: if (Qt.application.state === Qt.ApplicationActive)
                         root.showToast(name + " opent nog niet. Duurt het lang? Kies de tegel nog een keer.", 6000)
    }
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state !== Qt.ApplicationActive) {
                launchSlowTimer.stop()
                toastTimer.stop()
            }
        }
    }

    function openTileMenu(model, row, focusItem) {
        if (row < 0) {
            return
        }
        editModel = model
        editRow = row
        if (model === radio) {
            const entries = [{ label: "Luisteren", action: "radio-play" }, { label: "Radiozender toevoegen…", action: "radio-add" }]
            for (const dir of ["left", "right", "up", "down"]) {
                if (root.moveLimit(model, row, dir) > 0) entries.push({ label: root.moveLabels[dir] + " verplaatsen…", action: "move-" + dir })
            }
            entries.push(...sectionMoveEntries(model))
            if (!radio.isAddTile(row)) entries.push({ label: "Van startpagina verwijderen", action: "radio-remove" })
            entries.push(...commonMenuEntries())
            menu.open(model.nameAt(row), entries, focusItem)
            return
        }
        if (model === usage) {
            menu.open(model.nameAt(row), [
                { label: "Openen", action: "usage-open" },
                { label: "Uit Vaak gebruikt halen", action: "usage-remove" }
            ].concat(sectionMoveEntries(model)).concat(commonMenuEntries()), focusItem)
            return
        }
        if (model === resume) {
            menu.open(model.nameAt(row), [
                { label: "Verder kijken", action: "resume-play" },
                { label: "Uit deze rij halen", action: "resume-remove" }
            ].concat(sectionMoveEntries(model)).concat(commonMenuEntries()), focusItem)
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
        if (parental.enabled && model.pathAt) {
            entries.push(parental.isLocked(model.pathAt(row))
                         ? { label: "🔓 Kinderslot van deze tegel halen", action: "parental-unlock-tile" }
                         : { label: "🔒 Kinderslot op deze tegel", action: "parental-lock-tile" })
        }
        entries.push(...sectionMoveEntries(model))
        if (model.pathAt && model.pathAt(row) !== "bigscreen:radio-now") {
            entries.push({ label: "Van startpagina verwijderen", action: "hide" })
        }
        entries.push(...commonMenuEntries())
        menu.open(model.nameAt(row), entries, focusItem)
    }

    // Onderaan elk tegelmenu: de knoppen die vroeger in de bovenbalk stonden
    // Waar de focus na een menu heen gaat: de tegel waar je was, anders de bovenbalk
    function menuFocus() {
        return currentSection ? currentSection.grid : quickRow
    }

    function commonMenuEntries() {
        return [
            { label: "🌙  Slaaptimer…" + (sleepTimer.active ? "  (nog " + sleepTimer.remainingText + ")" : ""), action: "sleep-menu" },
            { label: "⚙  Instellingen…", action: "personalize-menu" },
            { label: "Annuleren", action: "" }
        ]
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
            { label: "Achtergrond wijzigen…", action: "background-menu" },
            { label: appModel.showHero ? "Grote naam en logo linksboven verbergen" : "Grote naam en logo linksboven tonen", action: "toggle-hero" },
            { label: appModel.fontScale > 1 ? "Tekst normaal" : "Tekst groter (kijken op afstand)", action: "font-scale" },
            { label: "Diensten kiezen…", action: "welcome" },
            { label: "Meer instellingen…", action: "more" }
        ]
        let hidden = appModel.hiddenCount
        for (const m of webModels) {
            hidden += m.hiddenCount
        }
        hidden += radio.hiddenCount
        if (hidden > 0) {
            entries.push({ label: "Verwijderde tegels terugzetten (" + hidden + ")", action: "unhide" })
        }
        entries.push({ label: "Release-info (versie " + updater.current + ")", action: "release-info" })
        entries.push({ label: "Sluiten", action: "" })
        menu.open("Instellingen", entries, root.menuFocus())
    }

    // --- Meer instellingen: kinderslot, weer, opnames, tv-afstandsbediening, bijwerken ---
    function openMoreMenu() {
        menu.open("Meer instellingen", [
            { label: "Profielen…  (" + profiles.currentName + ")", action: "profiles" },
            { label: "Kinderslot…  (" + (parental.enabled ? "aan" : "uit") + ")", action: "parental" },
            { label: "Nachtmodus: " + nightModeLabel(), action: "night" },
            { label: "Bij opstarten radio hervatten: " + (appModel.setting("resumeRadio", false) ? "aan" : "uit"), action: "resume-radio" },
            { label: "Weinig gebruikte rijen inklappen: " + (appModel.setting("autoCollapse", true) ? "aan" : "uit"), action: "auto-collapse" },
            { label: "Weer…  (" + (weather.enabled ? (weather.place || "aan") : "uit") + ")", action: "weather" },
            { label: "Opnames opruimen…", action: "cleanup-settings" },
            { label: "Tv-afstandsbediening (HDMI-CEC)…", action: "cec" },
            { label: "Windows: wifi, bluetooth, beeld en geluid…", action: "windows" },
            { label: "Zoeken naar een nieuwe versie", action: "update-check" },
            { label: "Sluiten", action: "" }
        ], root.menuFocus(), "Kijkluister " + updater.current)
    }

    function nightModeLabel() {
        const m = appModel.setting("night", "auto")
        return m === "on" ? "altijd aan" : m === "off" ? "uit" : "automatisch (22–7 uur)"
    }

    // --- Profielen ---
    property bool pendingKidsProfile: false
    function openProfileMenu() {
        const entries = profiles.list.map(p => ({
            label: (p.current ? "✓  " : "      ") + p.name + (p.kids ? "  (kind)" : ""),
            action: p.current ? "" : "profile-switch:" + p.id }))
        if (!profiles.kids) {
            entries.push({ label: "Profiel toevoegen…", action: "profile-add" })
            entries.push({ label: "Kinderprofiel toevoegen…", action: "profile-add-kids" })
            for (const p of profiles.list) {
                if (p.id !== "" && !p.current) entries.push({ label: "Profiel " + p.name + " verwijderen", action: "profile-remove:" + p.id })
            }
        }
        entries.push({ label: "Sluiten", action: "" })
        menu.open("Profielen", entries, root.menuFocus(),
                  "Nu: " + profiles.currentName + ". Elk profiel heeft eigen tegels, rijen, radiozenders en Vaak gebruikt. Wisselen herstart Kijkluister.")
    }

    function openParentalMenu() {
        if (!parental.enabled) {
            menu.open("Kinderslot", [
                { label: "Kinderslot aanzetten…", action: "parental-set" },
                { label: "Sluiten", action: "" }
            ], root.menuFocus(), "Met een eigen pincode vergrendel je Live tv, Films, Series en tegels die je kiest. Zenders voor volwassenen zijn dan altijd vergrendeld.")
            return
        }
        menu.open("Kinderslot", [
            { label: "Nu vergrendelen", action: "parental-lock-now" },
            { label: "Pincode wijzigen…", action: "parental-change" },
            { label: "Kinderslot uitzetten…", action: "parental-off" },
            { label: "Sluiten", action: "" }
        ], root.menuFocus(), (parental.unlocked ? "Nu ontgrendeld (een uur na de pincode). " : "")
                     + "Vergrendelde tegels: kies een tegel, druk op Menu en kies Kinderslot.")
    }

    function askNewPin() {
        pinPad.ask("Nieuwe pincode", "Kies vier cijfers die kinderen niet weten.", (first) => {
            Qt.callLater(() => pinPad.ask("Pincode herhalen", "Vul dezelfde vier cijfers nog een keer in.", (second) => {
                if (second !== first) {
                    root.showToast("De pincodes waren niet gelijk. Probeer het opnieuw.", 5000)
                    return true
                }
                const wasOn = parental.enabled
                parental.setPin(first)
                root.showToast(wasOn ? "Nieuwe pincode ingesteld" : "Kinderslot staat aan: Live tv, Films en Series vragen nu om de pincode", 6000)
                return true
            }, root.menuFocus()))
            return true
        }, root.menuFocus())
    }

    function withPin(title, action) {
        pinPad.ask(title, "Vul de pincode van het kinderslot in.", (pin) => {
            if (!parental.check(pin)) return false
            action(pin)
            return true
        }, currentSection ? currentSection.grid : quickRow)
    }

    function openCleanupMenu() {
        const days = recorder.keepDays
        const gb = recorder.minFreeGb
        menu.open("Opnames opruimen", [
            { label: "Bewaren: " + (days > 0 ? days + " dagen" : "altijd") + "  (wijzigen)", action: "cleanup-days" },
            { label: "Ruimte vrijhouden: " + (gb > 0 ? gb + " GB" : "uit") + "  (wijzigen)", action: "cleanup-space" },
            { label: "Nu opruimen…", action: "cleanup-now" },
            { label: "Sluiten", action: "" }
        ], root.menuFocus(), recorder.diskText + ". Kijkluister vraagt het altijd eerst voordat er iets wordt gewist.")
    }

    function askCleanup(manual) {
        const list = recorder.cleanupCandidates()
        if (list.length === 0) {
            if (manual) showToast("Er hoeft niets opgeruimd te worden", 4000)
            return
        }
        let bytes = 0
        for (const r of list) bytes += r.size
        cleanupPaths = list.map(r => r.path)
        const sizeText = bytes >= 1e8 ? (bytes / 1e9).toFixed(1) + " GB" : Math.max(1, Math.round(bytes / 1e6)) + " MB"
        const names = list.slice(0, 3).map(r => "• " + r.name + " (" + r.date + ")").join("\n")
        menu.open(list.length === 1 ? "1 opname opruimen?" : list.length + " opnames opruimen?", [
            { label: "Wissen (" + sizeText + ")", action: "cleanup-confirm" },
            { label: "Laten staan", action: "" }
        ], currentSection ? currentSection.grid : quickRow,
           "Reden: " + list[0].reason + ".\n" + names + (list.length > 3 ? "\n… en " + (list.length - 3) + " meer" : ""))
    }
    property var cleanupPaths: []

    function openCecMenu() {
        const entries = []
        if (!cec.installed) {
            entries.push({ label: "libCEC ophalen en installeren", action: "cec-install" })
        } else {
            entries.push({ label: "Opnieuw verbinden", action: "cec-start" })
        }
        entries.push({ label: "Sluiten", action: "" })
        menu.open("Tv-afstandsbediening", entries, root.menuFocus(),
                  (cec.installed ? cec.status + ". " : "")
                  + "Bedien Kijkluister met de afstandsbediening van je tv. Nodig: een USB-CEC-adapter van Pulse-Eight tussen computer en tv (HDMI).")
    }

    function openSleepMenu(focusItem) {
        const entries = [15, 30, 45, 60, 90].map(m => ({ label: m + " minuten", action: "sleep-" + m }))
        if (sleepTimer.active) {
            entries.unshift({ label: "Slaaptimer uitzetten", action: "sleep-0" })
        }
        entries.push({ label: "Annuleren", action: "" })
        menu.open("Slaaptimer", entries, focusItem || quickRow,
                  sleepTimer.active ? "Nog " + sleepTimer.remainingText + ". Daarna stoppen radio, tv en films vanzelf."
                                    : "Radio, tv en films stoppen vanzelf na de gekozen tijd.")
    }

    function handleMenuAction(action) {
        if (action === "background-menu") {
            const bg = [
                { label: "Gratis foto zoeken…", action: "background-photo" },
                { label: "Eigen afbeelding kiezen…", action: "background" }
            ]
            if (appModel.background !== "") bg.push({ label: "Standaardachtergrond herstellen", action: "background-reset" })
            bg.push({ label: "Annuleren", action: "" })
            menu.open("Achtergrond wijzigen", bg, root.menuFocus(),
                      photos.source === "Unsplash" ? "Gratis foto's van Unsplash." : "Gratis foto's met een vrije licentie (Openverse).")
        } else if (action === "background-photo") {
            openPicker("photo", "Gratis foto als achtergrond", root.menuFocus(), "landschap")
        } else if (action === "release-info") {
            releaseInfo.open(root.menuFocus())
        } else if (action === "section-collapse") {
            toggleCollapsed(editModel)
        } else if (action === "usage-remove") {
            usage.remove(editRow)
        } else if (action === "usage-open") {
            launch(usage, editRow)
        } else if (action === "profiles") {
            openProfileMenu()
        } else if (action.startsWith("profile-switch:")) {
            const id = action.substring(15)
            if (profiles.kids && parental.enabled) {
                withPin("Ander profiel kiezen", () => profiles.switchTo(id))
            } else {
                profiles.switchTo(id)
            }
        } else if (action === "profile-add" || action === "profile-add-kids") {
            pendingKidsProfile = action === "profile-add-kids"
            if (pendingKidsProfile && !parental.enabled) {
                showToast("Stel eerst een pincode in voor het kinderslot", 5000)
                askNewPin()
                return
            }
            openPicker("name", pendingKidsProfile ? "Naam van het kinderprofiel" : "Naam van het nieuwe profiel", root.menuFocus())
        } else if (action.startsWith("profile-remove:")) {
            const pid = action.substring(15)
            const pname = profiles.nameOf(pid)
            profiles.remove(pid)
            showToast("Profiel " + pname + " verwijderd")
        } else if (action === "night") {
            const order = ["auto", "on", "off"]
            appModel.setSetting("night", order[(order.indexOf(appModel.setting("night", "auto")) + 1) % 3])
            openMoreMenu()
        } else if (action === "resume-radio") {
            appModel.setSetting("resumeRadio", !appModel.setting("resumeRadio", false))
            openMoreMenu()
        } else if (action === "auto-collapse") {
            appModel.setSetting("autoCollapse", !appModel.setting("autoCollapse", true))
            openMoreMenu()
        } else if (action === "section-up" || action === "section-down") {
            moveSection(editModel, action === "section-up" ? -1 : 1)
        } else if (action === "sleep-menu") {
            openSleepMenu(currentSection ? currentSection.grid : quickRow)
        } else if (action === "personalize-menu") {
            openPersonalizeMenu()
        } else if (action === "windows") {
            menu.open("Windows-instellingen", [
                { label: "Wifi", action: "uri:ms-settings:network-wifi" },
                { label: "Bluetooth (koptelefoon, controller, afstandsbediening)", action: "uri:ms-settings:bluetooth" },
                { label: "Beeldscherm", action: "uri:ms-settings:display" },
                { label: "Geluid", action: "uri:ms-settings:sound" },
                { label: "Alle instellingen", action: "uri:ms-settings:" },
                { label: "Sluiten", action: "" }
            ], root.menuFocus())
        } else if (action.startsWith("uri:")) {
            appModel.openUri(action.substring(4))
        } else if (action === "more") {
            openMoreMenu()
        } else if (action === "parental") {
            openParentalMenu()
        } else if (action === "parental-set") {
            askNewPin()
        } else if (action === "parental-change") {
            withPin("Pincode wijzigen", () => Qt.callLater(askNewPin))
        } else if (action === "parental-off") {
            withPin("Kinderslot uitzetten", (pin) => { parental.disable(pin); root.showToast("Kinderslot staat uit") })
        } else if (action === "parental-lock-now") {
            parental.lockNow()
            showToast("Vergrendeld")
        } else if (action === "parental-lock-tile") {
            parental.setLocked(editModel.pathAt(editRow), true)
            showToast("🔒 " + editModel.nameAt(editRow) + " vraagt nu om de pincode")
        } else if (action === "parental-unlock-tile") {
            const m = editModel, r = editRow
            withPin("Kinderslot van " + m.nameAt(r) + " halen", () => { parental.setLocked(m.pathAt(r), false); root.showToast(m.nameAt(r) + " is niet meer vergrendeld") })
        } else if (action === "weather") {
            menu.open("Weer", [
                { label: "Plaats kiezen…", action: "weather-place" },
                { label: weather.enabled ? "Weer niet tonen" : "Weer tonen", action: "weather-toggle" },
                { label: "Sluiten", action: "" }
            ], root.menuFocus(), weather.available ? weather.place + ": " + weather.summary + " (Open-Meteo)" : "Het weer staat naast de klok (Open-Meteo).")
        } else if (action === "weather-place") {
            openPicker("place", "Plaats voor het weer", root.menuFocus())
        } else if (action === "weather-toggle") {
            weather.enabled = !weather.enabled
        } else if (action === "cleanup-settings") {
            openCleanupMenu()
        } else if (action === "cleanup-days") {
            menu.open("Opnames bewaren", [0, 7, 14, 30, 60, 90].map(d => ({ label: d === 0 ? "Altijd" : d + " dagen", action: "cleanup-days-" + d })), root.menuFocus())
        } else if (action.startsWith("cleanup-days-")) {
            recorder.keepDays = parseInt(action.substring(13))
            openCleanupMenu()
        } else if (action === "cleanup-space") {
            menu.open("Ruimte vrijhouden op de schijf", [0, 5, 10, 25, 50].map(g => ({ label: g === 0 ? "Uit" : g + " GB", action: "cleanup-space-" + g })), quickRow,
                      "Is de schijf voller, dan stelt Kijkluister voor de oudste opnames te wissen.")
        } else if (action.startsWith("cleanup-space-")) {
            recorder.minFreeGb = parseInt(action.substring(14))
            openCleanupMenu()
        } else if (action === "cleanup-now") {
            askCleanup(true)
        } else if (action === "cleanup-confirm") {
            const n = recorder.cleanup(cleanupPaths)
            showToast(n === 1 ? "1 opname gewist" : n + " opnames gewist")
        } else if (action === "cec") {
            openCecMenu()
        } else if (action === "cec-install") {
            cec.install()
            showToast("libCEC wordt opgehaald…", 5000)
        } else if (action === "cec-start") {
            cec.start()
        } else if (action === "update-check") {
            updater.check(true)
            showToast("Zoeken naar een nieuwe versie…")
        } else if (action === "update-install") {
            updater.install()
        } else if (action === "update-later") {
            updater.dismiss()
        } else if (action.startsWith("sleep-")) {
            sleepTimer.set(parseInt(action.substring(6)))
        } else if (action === "radio-add") {
            openRadioSearch()
        } else if (action === "radio-remove") {
            const name = radio.nameAt(editRow)
            if (radioPlayer.row === editRow) radioPlayer.stopPlayback()
            radio.remove(editRow)
            showToast(name + " verwijderd")
        } else if (action === "quit") {
            Qt.quit()
        } else if (action === "resume-play") {
            launch(resume, editRow)
        } else if (action === "radio-play") {
            launch(radio, editRow)
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
        } else if (action === "font-scale") {
            appModel.fontScale = appModel.fontScale > 1 ? 1.0 : 1.25
            showToast(appModel.fontScale > 1 ? "Tekst is nu groter" : "Tekst is weer normaal")
        } else if (action === "welcome") {
            welcomeOverlay.open(root.menuFocus())
        } else if (action === "toggle-hero") {
            appModel.showHero = !appModel.showHero
        } else if (action === "hide") {
            const name = editModel.nameAt(editRow)
            editModel.hide(editRow)
            showToast(name + " verwijderd")
        } else if (action === "add") {
            addOverlay.open(root.menuFocus())
        } else if (action === "background") {
            imageDialog.purpose = "background"
            imageDialog.title = "Achtergrond kiezen"
            imageDialog.open()
        } else if (action === "background-reset") {
            appModel.clearBackground()
        } else if (action === "unhide") {
            radio.restoreHidden()
            appModel.restoreHidden()
            for (const m of webModels) {
                m.restoreHidden()
            }
            showToast("Alle tegels staan weer op de startpagina")
        }
    }

    // Schermafbeeldingen van de verbeteringen (alleen via BIGSCREEN_SELFTEST=u-...)
    function runImprovementShot(mode) {
        appModel.fontScale = mode === "u-bigtext" ? 1.25 : 1.0
        iptv.search = ""
        const testSource = () => {
            if (!iptv.sources.some(s => s.name === "Gids-test")) iptv.addSource("m3u-file", "Gids-test", selfTestM3u, "", "")
        }
        const mediaIndex = () => sectionDefs.findIndex(d => d.model === appModel)
        if (mode === "u-library") {
            libraryScreen.open("movies", mediaGrid())
        } else if (mode === "u-home" || mode === "u-bigtext") {
            focusSection(0, 0, false)
        } else if (mode === "u-header") {
            quickRow.currentIndex = 0
            quickRow.forceActiveFocus()
        } else if (mode === "u-quit") {
            let quit = 0
            for (let i = 0; i < quickModel.count; ++i) if (quickModel.get(i).uri === "") quit = i
            quickRow.currentIndex = quit
            quickRow.forceActiveFocus()
            quickRow.trigger(quit)
        } else if (mode === "u-personalize") {
            openPersonalizeMenu()
        } else if (mode === "u-welcome") {
            welcomeOverlay.open(mediaGrid())
        } else if (mode === "u-sources") {
            testSource()
            iptvScreen.open(mediaGrid())
            iptvScreen.openSources()
        } else if (mode === "u-error") {
            iptv.addFreeSources(false)
            iptv.group = "Nederland"
            iptv.search = "NPO 1"
            iptvScreen.autoPlay = true
            iptvScreen.open(mediaGrid())
        } else if (mode === "u-guiderecord") {
            testSource()
            recorder.folder = selfTestRecordDir
            iptv.group = "Alle zenders"
            iptvScreen.autoPlay = true
            iptvScreen.autoGuide = true
            iptvScreen.autoGuideRecord = true
            iptvScreen.guideStart = 3
            iptvScreen.open(mediaGrid())
        } else if (mode === "u-badge") {
            Qt.callLater(() => focusSection(mediaIndex(), 2, false))
        } else if (mode === "u-recordpanel") {
            testSource()
            recorder.folder = selfTestRecordDir
            iptv.group = "Alle zenders"
            iptvScreen.autoPlay = true
            iptvScreen.autoRecord = "panelonly"
            iptvScreen.open(mediaGrid())
        } else if (mode === "u-libsetup") {
            libraryScreen.open("movies", mediaGrid())
            libraryScreen.openSetup()
            libraryScreen.demoPin()
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
        startWhereLeft.start()
        // Eerste keer: welkomststap (diensten kiezen)
        if ((selfTest === "" && !appModel.welcomeDone) || selfTest === "welcome") {
            Qt.callLater(() => welcomeOverlay.open(mediaGrid()))
        }
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
            iptv.group = "Alle zenders"   // test: de testzenders staan niet in de groep Nederland
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
            const kinds = { "frame-chicago": 0, "frame-met": 1, "frame-nature": 2, "frame-unsplash": 3, "frame-mix": 4, "frame-lijst": 0, "frame-settings": 2, "frame-esc": 2, "frame-mouseesc": 0 }
            frame.source = kinds[selfTest] !== undefined ? kinds[selfTest] : 0
            frame.fill = selfTest !== "frame-lijst"
            frame.interval = 5
            frameScreen.open(mediaGrid())
            if (selfTest === "frame-settings") {
                frameScreen.openSettings()
            }
        } else if (selfTest === "record" || selfTest === "recordpanel") {
            iptv.group = "Alle zenders"   // test: de testzenders staan niet in de groep Nederland
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
        } else if (selfTest.startsWith("u-")) {
            root.runImprovementShot(selfTest)
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
        } else if (selfTest === "radio") {
            // Test: alle zeven zenders na elkaar laten spelen (log: "Radio playing")
            radioPlayer.open(0, mediaGrid())
            radioTestTimer.start()
        } else if (selfTest === "search") {
            Qt.callLater(() => root.openPicker("all", "Zoeken", quickRow, "npo"))
            testStep.run(2500, () => { if (picker.results.length > 0) console.info("Search results", picker.results.length) })
        } else if (selfTest === "radioadd") {
            Qt.callLater(() => { root.openRadioSearch(); picker.text = "gelderland" })
            testStep.run(8000, () => { root.pickResult(0); console.info("Radio count", radio.count) })
        } else if (selfTest === "parental") {
            parental.setPin("2468")
            console.info("Parental check wrong", parental.check("1111"))
            console.info("Parental check right", parental.check("2468"))
            parental.lockNow()
            testStep.run(1500, () => {
                for (let r = 0; r < appModel.count; ++r) {
                    if (appModel.pathAt(r) === "bigscreen:iptv") root.launch(appModel, r)
                }
                pinPad.press("1"); pinPad.press("3")
            })
        } else if (selfTest === "sleep") {
            radioPlayer.open(0, mediaGrid())
            sleepTimer.setSeconds(10)
        } else if (selfTest === "weather") {
            weather.refresh()
            Qt.callLater(() => focusSection(0, 0, false))
        } else if (selfTest === "update") {
            updater.check(true)
        } else if (selfTest === "cec") {
            Qt.callLater(() => focusSection(0, 0, false))
            testStep.run(2000, () => {
                cec.parseLine("NOTICE:  [    1532]	connection opened")
                cec.parseLine("DEBUG:   [    2012]	key pressed: right (4) current(ff) duration(0)")
                cec.parseLine("DEBUG:   [    2112]	key released: right (4) D:100ms")
                cec.parseLine("DEBUG:   [    2312]	key pressed: right (4) current(ff) duration(0)")
                cec.parseLine("DEBUG:   [    2412]	key released: right (4) D:100ms")
            })
        } else if (selfTest === "cleanup") {
            recorder.folder = selfTestRecordDir
            recorder.keepDays = 30
            testStep.run(1500, () => recorder.checkCleanup(true))
        } else if (selfTest === "radiobg") {
            radioPlayer.open(0, mediaGrid())
            testStep.run(5000, () => {
                radioPlayer.close()
                Qt.callLater(() => focusSection(sectionDefs.findIndex(d => d.model === appModel), 0, false))
            })
        } else if (selfTest === "regional") {
            // Tegel Regionale tv: lijst, daarna eerste zender afspelen
            testStep.run(1500, () => {
                for (let r = 0; r < appModel.count; ++r) if (appModel.pathAt(r) === "bigscreen:regional") root.launch(appModel, r)
                console.info("Regional count", iptv.count, iptv.group)
                testStep.run(2500, () => iptvScreen.play(3))
            })
        } else if (selfTest === "nowplaying") {
            radioPlayer.open(0, mediaGrid())
            testStep.run(4000, () => {
                radioPlayer.close()
                Qt.callLater(() => {
                    focusSection(sectionDefs.findIndex(d => d.model === appModel), 0, false)
                    console.info("Media first tile:", appModel.nameAt(0))
                })
            })
        } else if (selfTest === "sections") {
            appModel.sectionOrder = []
            console.info("Section order default:", sectionDefs.map(d => d.title).join(","))
            moveSection(radio, -1)
            console.info("Section order moved:", sectionDefs.map(d => d.title).join(","))
            radio.move(radio.count - 1, 0)
            console.info("Radio first tile:", radio.nameAt(0), radio.count)
            Qt.callLater(() => focusSection(sectionDefs.findIndex(d => d.model === radio), 0, false))
        } else if (selfTest === "homekey") {
            homeBridge.externalLaunched()
            testStep.run(1500, () => homeBridge.goHome())
        } else if (selfTest === "releaseinfo") {
            Qt.callLater(() => releaseInfo.open(quickRow))
        } else if (selfTest === "news") {
            Qt.callLater(() => focusSection(sectionDefs.findIndex(d => d.model === webNews), 0, false))
        } else if (selfTest === "photo") {
            Qt.callLater(() => root.openPicker("photo", "Gratis foto als achtergrond", quickRow, "bos"))
        } else if (selfTest === "settingsmenu") {
            Qt.callLater(() => root.openPersonalizeMenu())
        } else if (selfTest === "usage") {
            // Een paar keer iets openen: rij Vaak gebruikt verschijnt bovenaan
            usage.record("video", webVideo.pathAt(0)); usage.record("video", webVideo.pathAt(0))
            usage.record("video", webVideo.pathAt(1)); usage.record("radio", radio.pathAt(0))
            usage.record("media", appModel.pathAt(0))
            console.info("Usage count", usage.count, usage.nameAt(0))
            Qt.callLater(() => focusSection(0, 0, false))
        } else if (selfTest === "help") {
            Qt.callLater(() => helpOverlay.open(quickRow))
        } else if (selfTest === "night") {
            Qt.callLater(() => focusSection(0, 0, false))
        } else if (selfTest === "profiles") {
            const pid = profiles.add("Petra", false)
            console.info("Profiles count", profiles.count, profiles.nameOf(pid))
            Qt.callLater(() => openProfileMenu())
        } else if (selfTest === "collapse") {
            appModel.setSetting("collapsed", ["Podcasts"])
            console.info("Collapsed Podcasts:", isCollapsed("Podcasts", webPodcasts))
            Qt.callLater(() => focusSection(0, 0, false))
        } else if (selfTest === "radiohome") {
            Qt.callLater(() => focusSection(sectionDefs.findIndex(d => d.model === radio), 0, false))
        } else if (selfTest === "resume") {
            // Test: tegel Verder kijken in de rij Media openen (geschiedenis door de test klaargezet)
            testStep.run(2000, () => {
                for (let r = 0; r < appModel.count; ++r) if (appModel.pathAt(r) === "bigscreen:resume") root.launch(appModel, r)
            })
        } else if (selfTest === "epgrecord") {
            iptv.group = "Alle zenders"   // test: de testzenders staan niet in de groep Nederland
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
        } else if (selfTest === "librarysetup" || selfTest === "libraryunlock") {
            libraryScreen.open("movies", mediaGrid())
            libraryScreen.openSetup()
            if (selfTest === "libraryunlock") {
                // Test: verkeerde en juiste pincode
                console.info("Unlock test wrong:", library.unlock("0000"), "right:", library.unlock("1973"))
            }
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
        ListElement { label: "Zoeken"; code: 0xE721; uri: "search"; about: "Zoek apps, zenders, programma's, films en radio" }
        ListElement { label: "Hulp"; code: 0xE897; uri: "help"; about: "Welke knop doet wat?" }
        ListElement { label: "Instellingen"; code: 0xE713; uri: "personalize"; about: "Tegels, achtergrond, kinderslot en meer" }
        ListElement { label: "Sluiten"; code: 0xE711; uri: ""; about: "Kijkluister sluiten (de computer blijft aan)" }
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
            font.pixelSize: (root.unit * 3.2) * appModel.fontScale
            font.weight: Font.DemiBold
            text: "Kijkluister"
        }

        Text {
            id: clock
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: "white"
            font.pixelSize: (root.unit * 3.2) * appModel.fontScale
        }
        Text {
            id: dateLabel
            anchors.right: clock.left
            anchors.rightMargin: root.unit * 2
            anchors.baseline: clock.baseline
            color: "#c4c7cc"
            font.pixelSize: (root.unit * 2.4) * appModel.fontScale
        }
        // Weer (Open-Meteo) en de slaaptimer naast de datum
        Row {
            id: statusRow
            anchors.right: dateLabel.left
            anchors.rightMargin: root.unit * 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.unit * 1.6
            Text {
                visible: sleepTimer.active
                anchors.verticalCenter: parent.verticalCenter
                text: "🌙 " + sleepTimer.remainingText
                color: "#c4c7cc"
                font.pixelSize: (root.unit * 2.4) * appModel.fontScale
            }
            Text {
                id: weatherLabel
                visible: weather.available
                anchors.verticalCenter: parent.verticalCenter
                text: weather.icon + " " + weather.summary
                color: "#c4c7cc"
                font.pixelSize: (root.unit * 2.4) * appModel.fontScale
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.handleMenuAction("weather")
                }
            }
        }
    }

    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            const now = new Date()
            clock.text = Qt.formatTime(now, "HH:mm")
            dateLabel.text = now.toLocaleDateString(Qt.locale("nl_NL"), "dddd d MMMM")
        }
    }

    // --- Snelknoppen in de bovenbalk ---
    ListView {
        id: quickRow
        z: 5   // labeltje onder een knop valt over het tekstvlak eronder
        anchors.verticalCenter: header.verticalCenter
        anchors.left: header.left
        anchors.leftMargin: brand.x + brand.width + root.unit * 3
        width: Math.min(root.unit * 19 * quickModel.count,
                        header.width - brand.x - brand.width - clock.width - dateLabel.width - statusRow.width - root.unit * 12)
        height: root.unit * 5.6
        orientation: ListView.Horizontal
        model: quickModel
        keyNavigationEnabled: true
        interactive: false

        function trigger(index) {
            const item = quickModel.get(index)
            if (item.uri === "") {
                // Eerst vragen: de computer blijft aan, geplande opnames gaan niet door
                menu.open("Kijkluister sluiten?", [
                    { label: "Sluiten", action: "quit" },
                    { label: "Annuleren", action: "" }
                ], root.menuFocus(), recorder.schedule.length > 0
                    ? "Je computer blijft aan. Geplande opnames gaan niet door zolang Kijkluister dicht is."
                    : "Je computer blijft aan.")
            } else if (item.uri === "personalize") {
                root.openPersonalizeMenu()
            } else if (item.uri === "help") {
                helpOverlay.open(quickRow)
            } else if (item.uri === "profile") {
                root.openProfileMenu()
            } else if (item.uri === "sleep") {
                root.openSleepMenu(quickRow)
            } else if (item.uri === "search") {
                root.openPicker("all", "Zoeken", root.menuFocus())
            } else if (item.uri === "sleep") {
                root.openSleepMenu(quickRow)
            } else if (item.uri === "radio") {
                radioPlayer.show(quickRow)
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
        // Ingeklapt als er (nog) niets te tonen is, zodat er geen leeg vlak boven de rijen staat
        readonly property bool filled: root.heroShown && root.focusName !== ""
        height: filled ? root.unit * 21 : root.unit * 1
        opacity: filled ? 1 : 0
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
                font.pixelSize: (root.unit * 7.5) * appModel.fontScale
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                text: root.focusName
            }
            Text {
                color: "#c4c7cc"
                font.pixelSize: (root.unit * 2.4) * appModel.fontScale
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
                    collapsed: root.isCollapsed(modelData.title, modelData.model)
                    columns: root.columns
                    unit: root.unit
                    canHover: () => !menu.visible && !addOverlay.visible && !placesPicker.visible && !picker.visible && !pinPad.visible && root.mouseActive()
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

    HintBar {
        id: hint
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: root.unit * 1.5
        unit: root.unit
        items: [
            { pad: "✛", key: "Pijltjes", label: "Kiezen" },
            { pad: "A", key: "Enter", label: "Openen" },
            { pad: "X", key: "Menu", label: "Opties" },
            { pad: "", key: "Rechtermuisknop", label: "Opties" }
        ]
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
            font.pixelSize: (root.unit * 2.6) * appModel.fontScale
        }
    }
    Timer { id: toastTimer; interval: 3500 }

    // Eenmalige tip, de eerste keer op het startscherm
    Timer {
        id: tipTimer
        interval: 2500
        running: selfTest === "" && appModel.welcomeDone && !appModel.tipShown("hold")
        onTriggered: {
            appModel.markTipShown("hold")
            root.showToast("Tip: houd " + (gamepad.connectedCount > 0 ? "Ⓐ" : "Enter") + " ingedrukt om een tegel te verplaatsen of te verwijderen", 7000)
        }
    }

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
        onPinRequired: (row) => pinPad.ask(iptv.channelAt(row).name + " is vergrendeld", "Zender voor volwassenen. Vul de pincode van het kinderslot in.",
                                           (pin) => { if (!parental.check(pin)) return false; iptvScreen.play(row); return true }, iptvScreen)
        id: iptvScreen
    }

    // Schilderij: kunst of natuurfoto's
    FrameScreen {
        id: frameScreen
    }

    // Welkomststap: welke diensten gebruik je
    WelcomeOverlay {
        id: welcomeOverlay
        onDone: root.showToast("Klaar! Kies een tegel en druk op " + (gamepad.connectedCount > 0 ? "Ⓐ" : "Enter") + " om te beginnen")
    }

    // Melding als Kijkluister MPC-HC of ffmpeg ophaalt (op de achtergrond): bovenaan, uit de weg
    Rectangle {
        z: 950
        visible: components.status !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.height * 0.02
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
                font.pixelSize: (root.height * 0.024) * appModel.fontScale
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

    // Radio: zenders luisteren in Kijkluister zelf
    RadioPlayer {
        id: radioPlayer
        sleepText: sleepTimer.active ? sleepTimer.remainingText : ""
        onSleepRequested: root.openSleepMenu(radioPlayer)
        // Speelt hij op de achtergrond: knop "Radio" in de bovenbalk
        onInBackgroundChanged: root.syncRadioButton()
        onRowChanged: root.syncRadioButton()
    }

    // Speelt de radio op de achtergrond: tegel "Nu op de radio" vooraan in de rij Media
    function syncRadioButton() {
        if (radioPlayer.inBackground) {
            const icon = radio.iconAt(radioPlayer.row)
            appModel.setNowPlaying(radio.nameAt(radioPlayer.row), icon.startsWith("glyph:") ? "" : icon, radio.accentAt(radioPlayer.row))
        } else {
            appModel.setNowPlaying("", "", "")
        }
    }

    Connections {
        target: radio
        function onAddRequested() { root.openRadioSearch() }
    }

    // --- Slaaptimer: na de gekozen tijd stopt alles wat speelt ---
    Item {
        id: sleepTimer
        property double endAt: 0
        property double now: Date.now()
        readonly property bool active: endAt > 0
        readonly property int remainingMinutes: active ? Math.max(0, Math.ceil((endAt - now) / 60000)) : 0
        readonly property string remainingText: remainingMinutes + " min"

        function set(minutes) {
            setSeconds(minutes * 60)
            root.showToast(minutes > 0 ? "Slaaptimer: over " + minutes + " minuten stopt alles" : "Slaaptimer staat uit")
        }
        function setSeconds(seconds) {
            endAt = seconds > 0 ? Date.now() + seconds * 1000 : 0
            now = Date.now()
            warned = false
            console.info("Sleep timer", seconds, "s")
        }
        property bool warned: false

        Timer {
            interval: 1000
            repeat: true
            running: sleepTimer.active
            onTriggered: {
                sleepTimer.now = Date.now()
                const left = sleepTimer.endAt - sleepTimer.now
                if (!sleepTimer.warned && left < 60000 && left > 5000) {
                    sleepTimer.warned = true
                    root.showToast("Slaaptimer: over een minuut stopt alles", 8000)
                }
                if (left <= 0) {
                    sleepTimer.endAt = 0
                    root.sleepNow()
                }
            }
        }
    }

    function sleepNow() {
        console.info("Sleep timer fired")
        radioPlayer.stopPlayback()
        if (iptvScreen.visible) iptvScreen.close()
        mpc.stop()
        showToast("Slaaptimer: alles is gestopt. Welterusten!", 10000)
    }

    // --- Zoeken (alles, radiozenders, plaats voor het weer) ---
    property string pickerMode: ""
    property var pickerItems: []

    function openPicker(mode, title, focusItem, startText) {
        pickerMode = mode
        picker.iconScale = mode === "photo" ? 2 : 1
        picker.voice = mode === "all" || mode === "radio" || mode === "photo"
        picker.placeholder = mode === "radio" ? "Naam van de zender, bv. Omroep Gelderland"
                           : mode === "photo" ? "Waar wil je een foto van? Bv. bos, zee, bergen"
                           : mode === "place" ? "Naam van je woonplaats"
                           : "Zoek een app, zender, programma, film of radiozender"
        picker.pickLabel = mode === "radio" ? "Toevoegen" : mode === "place" || mode === "photo" ? "Kiezen" : "Openen"
        picker.emptyText = mode === "radio" ? "Geen zender gevonden. Probeer een ander woord." : "Niets gevonden"
        picker.open(title, focusItem, startText)
    }

    function openRadioSearch() {
        const section = sectionFor(radio)
        openPicker("radio", "Radiozender toevoegen", section ? section.grid : quickRow)
    }

    function searchAll(q) {
        const items = []
        if (q.length < 2) return items
        const lower = q.toLowerCase()
        const models = [appModel].concat(webModels)
        for (const m of models) {
            for (let r = 0; r < m.count; ++r) {
                const name = m.nameAt(r)
                if (name.toLowerCase().indexOf(lower) >= 0) {
                    const icon = m.iconAt(r)
                    items.push({ name: name, detail: "", icon: icon.startsWith("glyph:") ? icon : icon, section: "Apps en diensten",
                                 kind: "app", model: m, row: r, badge: parental.enabled && parental.isLocked(m.pathAt(r)) ? "🔒" : "" })
                }
            }
        }
        for (let r = 0; r < radio.count; ++r) {
            if (radio.isStation(r) && radio.nameAt(r).toLowerCase().indexOf(lower) >= 0) {
                items.push({ name: radio.nameAt(r), detail: radio.subtitleAt(r), icon: radio.iconAt(r), section: "Radio", kind: "radio", row: r })
            }
        }
        const lib = []
        for (const item of library.movies.concat(library.shows)) {
            if ((item.title || "").toLowerCase().indexOf(lower) >= 0) {
                lib.push({ name: item.title, detail: (item.kind === "show" ? "Serie" : "Film") + (item.year ? " · " + item.year : ""),
                           icon: item.localPoster || item.poster || "glyph:\uE8B2", section: "Films en series", kind: "library", item: item })
            }
        }
        items.push(...lib.slice(0, 20))
        for (const r of iptv.searchAll(q, 25)) {
            const programme = r.kind === "programme"
            const scheduled = programme && recorder.isScheduled(r.url, r.startSecs)
            items.push({ name: r.name, detail: r.detail, icon: r.icon || "glyph:\uE7F4",
                         section: programme ? "Tv-gids" : "Live tv", kind: r.kind, data: r,
                         badge: programme ? (r.isNow ? "Nu op tv" : scheduled ? "● Opname gepland" : "Menu: opnemen") : "" })
        }
        return items
    }

    SearchPicker {
        id: picker
        onQuery: (q) => {
            if (root.pickerMode === "radio") {
                radio.searchStations(q)
            } else if (root.pickerMode === "photo") {
                photos.search(q)
            } else if (root.pickerMode === "name") {
                picker.results = q.length > 0 ? [{ name: "Opslaan als “" + q + "”", detail: "Enter om het profiel te maken", icon: "glyph:\uE77B" }] : []
            } else if (root.pickerMode === "place") {
                if (q.length >= 2) weather.searchPlaces(q)
            } else {
                root.pickerItems = root.searchAll(q)
                picker.results = root.pickerItems
                console.info("Search", q, root.pickerItems.length)
            }
        }
        onPicked: (index) => root.pickResult(index)
        onSecondary: (index) => root.pickResult(index, true)
    }
    Connections {
        target: radio
        function onResultsChanged() {
            if (root.pickerMode !== "radio") return
            picker.busy = radio.searching
            picker.results = radio.results.map((r, i) => ({ name: r.name, detail: r.detail, icon: r.logo,
                                                             badge: radio.hasResult(i) ? "✓ Toegevoegd" : "" }))
        }
    }
    Connections {
        target: photos
        function onResultsChanged() {
            if (root.pickerMode !== "photo") return
            picker.busy = photos.busy
            picker.results = photos.results.map(p => ({ name: p.name, detail: p.detail, icon: p.thumb }))
        }
        function onDownloaded(file, credit) {
            if (appModel.setBackground(file)) {
                picker.close()
                root.showToast("Nieuwe achtergrond. " + credit, 6000)
            }
        }
        function onFailed(message) { root.showToast(message, 5000) }
    }
    Connections {
        target: weather
        function onPlacesChanged() {
            if (root.pickerMode !== "place") return
            picker.results = weather.places.map(p => ({ name: p.name, detail: p.detail, icon: "📍" }))
        }
    }

    function pickResult(index, secondary) {
        if (index < 0) return
        if (pickerMode === "radio") {
            if (radio.addResult(index)) {
                showToast(picker.nameAt(index) + " staat nu in de rij Radio")
                picker.results = radio.results.map((r, i) => ({ name: r.name, detail: r.detail, icon: r.logo,
                                                                 badge: radio.hasResult(i) ? "✓ Toegevoegd" : "" }))
            } else {
                showToast(picker.nameAt(index) + " staat al in de rij Radio")
            }
            return
        }
        if (pickerMode === "name") {
            const name = picker.text.trim()
            if (name === "") return
            const id = profiles.add(name, pendingKidsProfile)
            picker.close()
            menu.open("Profiel " + name + " is gemaakt", [
                { label: "Nu naar " + name + " wisselen", action: "profile-switch:" + id },
                { label: "Later", action: "" }
            ], root.menuFocus())
            return
        }
        if (pickerMode === "photo") {
            showToast("Foto wordt opgehaald…", 20000)
            photos.download(index)
            return
        }
        if (pickerMode === "place") {
            weather.choosePlace(index)
            picker.close()
            showToast("Weer voor " + picker.nameAt(index))
            return
        }
        const it = pickerItems[index]
        if (!it) return
        if (it.kind === "programme" && (secondary || !it.data.isNow)) {
            // Toekomstig programma: opnemen in- of uitplannen
            const d = it.data
            recorder.toggleSchedule(d.channel, d.url, d.name, d.startSecs, d.stopSecs)
            const on = recorder.isScheduled(d.url, d.startSecs)
            showToast(on ? "● Wordt opgenomen: " + d.name : "Opname geannuleerd: " + d.name, 5000)
            pickerItems[index].badge = on ? "● Opname gepland" : "Menu: opnemen"
            picker.results = pickerItems
            return
        }
        picker.visible = false
        const back = picker.returnFocusTo
        if (back) back.forceActiveFocus()
        if (it.kind === "app") {
            launch(it.model, it.row)
        } else if (it.kind === "radio") {
            radioPlayer.open(it.row, back || quickRow)
        } else if (it.kind === "library") {
            const open = () => {
                libraryScreen.open(it.item.kind === "show" ? "shows" : "movies", back || mediaGrid())
                libraryScreen.showDetail(it.item)
            }
            const path = "bigscreen:movies"
            if (parental.needsPin(path)) {
                pinPad.ask(it.name + " is vergrendeld", "Vul de pincode van het kinderslot in.", (pin) => { if (!parental.check(pin)) return false; open(); return true }, back || quickRow)
            } else {
                open()
            }
        } else {
            const playChannel = () => {
                radioPlayer.stopPlayback()
                iptvScreen.open(back || mediaGrid())
                const row = iptv.showChannel(it.data.url)
                if (row >= 0) iptvScreen.play(row)
            }
            if (parental.needsPin("bigscreen:iptv")) {
                pinPad.ask("Live tv is vergrendeld", "Vul de pincode van het kinderslot in.", (pin) => { if (!parental.check(pin)) return false; playChannel(); return true }, back || quickRow)
            } else {
                playChannel()
            }
        }
    }

    PinPad {
        id: pinPad
    }

    ReleaseInfo {
        id: releaseInfo
    }

    HelpOverlay {
        id: helpOverlay
    }

    // Nachtmodus: 22-7 uur (of altijd) gedimd en warmer beeld, radio zachter, slaaptimer in de bovenbalk
    property bool nightActive: false
    function updateNight() {
        const mode = appModel.setting("night", "auto")
        const h = new Date().getHours()
        nightActive = selfTest === "night" || mode === "on" || (mode === "auto" && (h >= 22 || h < 7))
    }
    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.updateNight()
    }
    Connections { target: appModel; function onSettingsChanged() { root.updateNight() } }
    onNightActiveChanged: {
        console.info("Night mode", nightActive)
        let index = -1
        for (let i = 0; i < quickModel.count; ++i) if (quickModel.get(i).uri === "sleep") index = i
        if (nightActive && index < 0) {
            quickModel.insert(1, { label: "Slaaptimer", code: 0xE708, uri: "sleep", about: "Radio, tv en films stoppen vanzelf" })
        } else if (!nightActive && index >= 0) {
            quickModel.remove(index)
        }
        radioPlayer.maxVolume = nightActive ? 0.5 : 1.0
    }
    Rectangle {
        anchors.fill: parent
        z: 400
        visible: root.nightActive
        color: "#3a1a0c00"   // warm en iets donkerder
        enabled: false
    }

    // Profielknop in de bovenbalk zodra er meer dan één profiel is
    Connections {
        target: profiles
        function onChanged() { root.syncProfileButton() }
    }
    function syncProfileButton() {
        let index = -1
        for (let i = 0; i < quickModel.count; ++i) if (quickModel.get(i).uri === "profile") index = i
        if (profiles.count > 1 && index < 0) {
            quickModel.insert(0, { label: profiles.currentName, code: 0xE77B, uri: "profile", about: "Ander profiel kiezen" })
        } else if (profiles.count <= 1 && index >= 0) {
            quickModel.remove(index)
        }
    }

    // Opstarten waar je was: kader op de laatst geopende tegel; radio eventueel hervatten
    Timer {
        id: startWhereLeft
        interval: 400
        onTriggered: {
            root.syncProfileButton()
            const cat = usage.lastCategory
            const src = cat !== "" ? usage.sourceModel(cat) : null
            const row = src ? usage.sourceRow(cat, usage.lastPath) : -1
            if (cat === "radio" && row >= 0 && appModel.setting("resumeRadio", false) && selfTest === "") {
                radioPlayer.open(row, mediaGrid())
                radioPlayer.close()
            }
            const sec = src ? sectionFor(src) : null
            if (sec && row >= 0 && !welcomeOverlay.visible && selfTest === "") {
                sec.grid.currentIndex = row
                sec.grid.forceActiveFocus()
                console.info("Start where left:", src.nameAt(row))
            }
        }
    }

    // Tegel Verder kijken (rij Media, naast Schilderij)
    ResumeScreen {
        id: resumeScreen
        onPlayRequested: (row) => { resumeScreen.visible = false; root.launch(resume, row) }
        onMenuRequested: (row) => {
            editModel = resume
            editRow = row
            menu.open(resume.nameAt(row), [
                { label: "Verder kijken", action: "resume-play" },
                { label: "Uit de lijst halen", action: "resume-remove" },
                { label: "Annuleren", action: "" }
            ], resumeScreen)
        }
    }
    Connections {
        target: resume
        function onCountChanged() { appModel.setResumeCount(resume.count) }
        Component.onCompleted: appModel.setResumeCount(resume.count)
    }

    // Stil bijwerken: klein bericht rechtsonder; installeren zodra er niets speelt
    Rectangle {
        id: updateBanner
        readonly property bool shown: updater.phase !== "" && !iptvScreen.visible && !libraryScreen.visible && !frameScreen.visible
                                      && !radioPlayer.visible && !picker.visible
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.unit * 2
        anchors.bottomMargin: root.unit * 7
        z: 40
        width: updateText.implicitWidth + root.unit * 4
        height: root.unit * 5
        radius: height / 2
        color: "#e61d2a40"
        border.color: "#55ffffff"
        border.width: 1
        opacity: shown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
        Text {
            id: updateText
            anchors.centerIn: parent
            color: "white"
            font.pixelSize: root.unit * 2 * appModel.fontScale
            text: updater.phase === "downloading" ? "⬇  Nieuwe versie " + updater.latest + " wordt op de achtergrond gedownload…"
                : updater.phase === "ready" ? "✓  Kijkluister " + updater.latest + " wordt geïnstalleerd zodra er niets speelt"
                : "⟳  Kijkluister " + updater.latest + " wordt geïnstalleerd en start zo opnieuw…"
        }
    }
    Timer {
        interval: 10000
        repeat: true
        running: updater.phase === "ready"
        onTriggered: {
            const idle = !radioPlayer.active && !iptvScreen.visible && !libraryScreen.visible && !mpc.running && !recorder.recording
                         && !homeBridge.external && !menu.visible && !picker.visible && !pinPad.visible && !frameScreen.visible
            if (idle) updater.installNow()
        }
    }

    // Zwevende Home-knop linksboven zolang een app of website voorop staat
    HomeButton {}

    // Home-toets, Home-knop, Esc lang ingedrukt of Guide op de controller: terug naar de tegels
    Connections {
        target: gamepad
        function onHomeRequested() { root.goHomeScreen() }
    }
    function goHomeScreen() {
        console.info("Home screen")
        if (menu.visible) menu.close()
        if (picker.visible) picker.close()
        if (pinPad.visible) pinPad.close()
        if (radioPlayer.visible) radioPlayer.close()
        if (iptvScreen.visible) iptvScreen.close()
        if (libraryScreen.visible) libraryScreen.close()
        if (frameScreen.visible) frameScreen.close()
        if (resumeScreen.visible) resumeScreen.close()
        if (releaseInfo.visible) releaseInfo.close()
        Qt.callLater(() => focusSection(0, 0, false))
    }

    // Alleen voor de tests: iets later uitvoeren
    Timer {
        id: testStep
        property var action: null
        function run(ms, fn) { action = fn; interval = ms; restart() }
        onTriggered: if (action) action()
    }

    // Opruimen van opnames: Kijkluister vraagt het eerst
    Connections {
        target: recorder
        function onCleanupSuggested(count, reason) {
            if (iptvScreen.visible || libraryScreen.visible || radioPlayer.visible || menu.visible) {
                return   // later nog eens (de opnemer vraagt het hooguit eens per dag)
            }
            root.askCleanup(false)
        }
    }

    // Nieuwe versie
    Connections {
        target: updater
        function onChecked(manual) {
            if (updater.silent && updater.updateAvailable) {
                if (manual) root.showToast("Kijkluister " + updater.latest + " wordt op de achtergrond opgehaald en geïnstalleerd", 6000)
            } else if (updater.shouldOffer() || (manual && updater.updateAvailable)) {
                menu.open("Kijkluister " + updater.latest + " is er", [
                    { label: "Nu bijwerken", action: "update-install" },
                    { label: "Later", action: "update-later" }
                ], root.currentSection ? root.currentSection.grid : quickRow,
                   "Je hebt nu " + updater.current + ". Bijwerken duurt ongeveer een minuut; daarna start Kijkluister vanzelf weer.")
            } else if (manual) {
                root.showToast(updater.status, 6000)
            }
        }
    }
    Connections {
        target: updater
        function onChanged() {
            if (updater.phase === "" && updater.busy && updater.progress > 0 && updater.status !== "") {
                root.showToast(updater.status + (updater.progress > 0 ? "  " + Math.round(updater.progress * 100) + "%" : ""), 60000)
            }
        }
    }
    Connections {
        target: cec
        function onChanged() {
            if (cec.connected) root.showToast("📺 Tv-afstandsbediening verbonden", 4000)
        }
    }
    // Test: volgende zender zodra deze speelt of echt niet lukt (reserve-adressen krijgen de tijd)
    Timer {
        id: radioTestTimer
        property int waited: 0
        interval: 1000
        repeat: true
        onTriggered: {
            waited += 1
            if (waited < 4 || (radioPlayer.loading && waited < 25)) {
                return
            }
            waited = 0
            const next = radio.nextStation(radioPlayer.row, 1)
            if (next <= radioPlayer.row) {
                stop()
            } else {
                radioPlayer.tune(next)
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
            if (target === "bigscreen:resume") {
                resumeScreen.open(mediaGrid())
            } else if (target === "bigscreen:radio-now") {
                radioPlayer.show(mediaGrid())
            } else if (target === "bigscreen:regional") {
                iptvScreen.open(mediaGrid(), "Regionale tv")
            } else if (target === "bigscreen:iptv") {
                iptvScreen.open(mediaGrid())
            } else if (target === "bigscreen:frame") {
                frameScreen.open(mediaGrid())
            } else {
                libraryScreen.open(target === "bigscreen:shows" ? "shows" : "movies", mediaGrid())
            }
        }
    }
}
