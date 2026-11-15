// Live tv: groepen en zoeken links, zenders als tegels, afspelen schermvullend
// in Bigscreen zelf. Pijltje omhoog/omlaag wisselt van zender tijdens het kijken.
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtMultimedia

FocusScope {
    id: tv

    readonly property real unit: height / 100
    property Item returnFocusTo: null
    property bool autoPlay: false          // alleen voor de geautomatiseerde test
    property bool playing: false
    property int playingRow: -1
    property var channel: ({})
    property string errorText: ""
    property bool pinInfo: false           // test: balk blijft staan
    property bool autoGuide: false         // test: gids openen na afspelen
    property string demo: ""               // schermafbeeldingen voor de handleiding
    property bool autoGuideRecord: false   // test: vanuit de gids opnemen
    property string autoRecord: ""         // test: "record" neemt op, "recordpanel" toont het venster
    property alias guideStart: guidePanel.startIndex
    // Gids van de zender die nu speelt; ververst als er nieuwe gidsgegevens zijn
    readonly property var nowNext: (iptv.epgRevision, epgClock.tick, playingRow >= 0 ? iptv.nowNext(playingRow) : ({}))
    // De speler bestaat alleen tijdens het kijken (snellere start, decoder weer vrij)
    readonly property var player: playerLoader.item ? playerLoader.item.mediaPlayer : null

    anchors.fill: parent
    visible: false
    z: 50

    function open(focusItem, group) {
        returnFocusTo = focusItem
        visible = true
        grid.forceActiveFocus()
        if (group) {
            // Tegel Regionale tv: meteen die groep, ook zonder eigen bron
            iptv.group = group
            grid.currentIndex = 0
        } else if (iptv.sources.length === 0) {
            sources.open()
        } else if (iptv.totalCount === 0 && !iptv.busy) {
            iptv.reload()
        } else if (autoPlay && iptv.count > 0) {
            autoPlay = false
            play(0)
        }
    }

    function openSources() {
        sources.open()
    }

    // Schermen klaarzetten voor de handleiding (alleen via BIGSCREEN_SELFTEST)
    Timer {
        id: demoTimer
        interval: 7000
        running: tv.demo !== "" && tv.visible
        onTriggered: {
            if (tv.demo === "m-channels") {
                grid.currentIndex = 6
                grid.forceActiveFocus()
            } else if (tv.demo === "m-search") {
                searchField.text = "tv"
                searchField.forceActiveFocus()
            } else if (tv.demo === "m-favorites") {
                for (const r of [0, 3, 5, 8]) iptv.toggleFavorite(r)
                iptv.group = "Favorieten"
                grid.currentIndex = 1
                grid.forceActiveFocus()
            } else if (tv.demo === "m-sources") {
                sources.open()
            } else if (tv.demo === "m-xtream") {
                sources.open()
                sources.demoXtream()
            } else if (tv.demo === "m-guidelist") {
                grid.currentIndex = 2
                tv.openGuide(2)
            }
        }
    }

    function close() {
        stop()
        visible = false
        if (returnFocusTo) {
            returnFocusTo.forceActiveFocus()
        }
    }

    signal pinRequired(int row)

    // Zender kiezen met cijfers (afstandsbediening): nummer = plaats in de huidige lijst
    property string numberEntry: ""
    function digit(d) {
        // 0 als eerste cijfer: terug naar de vorige zender
        if (d === "0" && numberEntry === "") {
            previousChannel()
            return
        }
        numberEntry = (numberEntry + d).slice(-4)
        numberTimer.restart()
    }
    Timer {
        id: numberTimer
        interval: 1500
        onTriggered: {
            const n = parseInt(tv.numberEntry) - 1
            tv.numberEntry = ""
            if (n >= 0 && n < iptv.count) {
                console.info("Channel by number", n + 1, iptv.channelAt(n).name)
                tv.play(n)
            }
        }
    }

    // Vorige zender (knop 0 of Backspace tijdens het kijken)
    property string previousUrl: ""
    function previousChannel() {
        if (previousUrl === "") {
            toast("Nog geen vorige zender")
            return
        }
        let row = iptv.rowOf(previousUrl)
        if (row < 0) row = iptv.showChannel(previousUrl)
        console.info("Previous channel", row)
        if (row >= 0) play(row)
    }
    function openGrid() {
        guideGrid.open(playing ? playingRow : Math.max(0, grid.currentIndex), playing ? playerView : grid)
    }

    function play(row) {
        const ch = iptv.channelAt(row)
        if (!ch.url) {
            return
        }
        if (playing && channel.url && channel.url !== ch.url) {
            previousUrl = channel.url
        }
        // Kinderslot: zenders voor volwassenen alleen met de pincode
        if (parental.enabled && !parental.unlocked && parental.isAdultChannel(ch.group || "", ch.name || "")) {
            pinRequired(row)
            return
        }
        playingRow = row
        channel = ch
        errorText = ""
        playing = true
        if (player) {
            player.stop()
            player.source = sourceFor(ch.url)
            player.play()
        }
        iptv.requestEpg(row)
        showInfo()
        playerView.forceActiveFocus()
        if (autoGuide) {
            autoGuide = false
            guideTestTimer.start()
        }
        if (autoRecord !== "") {
            const mode = autoRecord
            autoRecord = ""
            recordTestTimer.mode = mode
            recordTestTimer.start()
        }
    }
    Timer {
        id: guideTestTimer
        interval: 6000
        onTriggered: {
            tv.openGuide(tv.playingRow)
            if (tv.autoGuideRecord) {
                tv.autoGuideRecord = false
                guideRecordTimer.start()
            }
        }
    }
    Timer {
        id: guideRecordTimer
        interval: 2000
        onTriggered: {
            guidePanel.toggleRecord(0)   // loopt nu: begint meteen
            guidePanel.toggleRecord(3)   // later: gepland
        }
    }
    Timer {
        id: recordTestTimer
        property string mode: ""
        interval: 4000
        onTriggered: {
            const ch = iptv.channelAt(tv.playingRow)
            if (mode !== "panelonly") {
                recorder.start(ch.name, ch.url, 0)
            }
            if (mode === "recordpanel" || mode === "panelonly") {
                tv.openRecord(tv.playingRow)
            } else {
                recordStopTimer.start()
            }
        }
    }
    Timer { id: recordStopTimer; interval: 20000; onTriggered: recorder.stop() }

    // Wordt deze zender opgenomen, dan kijken we via de lokale doorgifte van de opname
    // (één verbinding met de aanbieder; veel abonnementen staan er maar één toe)
    function sourceFor(url) {
        return recorder.recording && recorder.url === url && recorder.relayUrl !== ""
               ? recorder.relayUrl + "?overrun_nonfatal=1&fifo_size=1000000&timeout=15000000" : url
    }

    Connections {
        target: recorder
        function onStateChanged() {
            if (!tv.playing || !tv.player || !tv.channel.url) {
                return
            }
            const wanted = tv.sourceFor(tv.channel.url)
            if (String(tv.player.source) !== wanted) {
                console.info("IPTV switch source:", wanted.startsWith("udp://") ? "relay" : "direct")
                tv.player.stop()
                tv.player.source = wanted
                tv.player.play()
            }
        }
    }

    function openRecord(row) {
        recordPanel.open(row >= 0 ? iptv.channelAt(row) : channel, playing ? playerView : grid)
    }

    function openGuide(row) {
        iptv.requestEpg(row)
        guidePanel.open(row, iptv.channelAt(row), playing ? playerView : grid)
    }

    function zap(delta) {
        if (iptv.count > 0) {
            play((playingRow + delta + iptv.count) % iptv.count)
        }
    }

    function stop() {
        if (player) {
            player.stop()
        }
        if (playing) {
            playing = false
            grid.currentIndex = Math.max(0, playingRow)
            grid.forceActiveFocus()
        }
    }

    function showInfo() {
        infoTimer.restart()
    }

    function toast(text) {
        message.text = text
        messageTimer.restart()
    }

    function toggleFavorite(row) {
        if (row < 0) {
            return
        }
        const name = iptv.channelAt(row).name
        iptv.toggleFavorite(row)
        toast(iptv.isFavorite(row) ? name + " toegevoegd aan Favorieten" : name + " uit Favorieten gehaald")
    }

    Keys.onEscapePressed: close()
    Keys.onBackPressed: close()

    Connections {
        target: iptv
        function onCountChanged() {
            if (tv.autoPlay && iptv.count > 0 && !tv.playing) {
                tv.autoPlay = false
                tv.play(0)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#14213a" }
            GradientStop { position: 1.0; color: "#0b0c0f" }
        }
    }

    // =====================================================================
    // Zenderoverzicht
    // =====================================================================
    Item {
        anchors.fill: parent
        visible: !tv.playing

        Rectangle {
            id: sidebar
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: tv.unit * 32
            color: "#a00b0c0f"

            Text {
                id: title
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: tv.unit * 4
                color: "white"
                font.pixelSize: (tv.unit * 3.6) * appModel.fontScale
                font.weight: Font.DemiBold
                text: "Live tv"
            }

            // Zoeken
            Rectangle {
                id: searchBox
                anchors.top: title.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: tv.unit * 3
                anchors.leftMargin: tv.unit * 2
                anchors.rightMargin: tv.unit * 2
                height: tv.unit * 6
                radius: height / 2
                color: "#0f1115"
                border.width: searchField.activeFocus ? 3 : 1
                border.color: searchField.activeFocus ? "#e8eaed" : "#33ffffff"
                Text {
                    id: searchIcon
                    anchors.left: parent.left
                    anchors.leftMargin: tv.unit * 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#9a9ea6"
                    font.family: "Segoe MDL2 Assets"
                    font.pixelSize: tv.unit * 2.2
                    text: ""
                }
                TextInput {
                    id: searchField
                    anchors.left: searchIcon.right
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: tv.unit * 1.5
                    anchors.rightMargin: tv.unit * 2
                    color: "white"
                    font.pixelSize: (tv.unit * 2.3) * appModel.fontScale
                    clip: true
                    selectByMouse: true
                    onTextChanged: searchTimer.restart()
                    Keys.onDownPressed: groupList.forceActiveFocus()
                    Keys.onReturnPressed: grid.forceActiveFocus()
                    Keys.onEnterPressed: grid.forceActiveFocus()
                    Keys.onRightPressed: (event) => {
                        if (cursorPosition === text.length) {
                            grid.forceActiveFocus()
                        } else {
                            event.accepted = false
                        }
                    }
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: searchField.text === "" && !searchField.activeFocus
                        color: "#a8acb3"
                        font.pixelSize: (tv.unit * 2.3) * appModel.fontScale
                        text: "Zender zoeken"
                    }
                }
                Timer {
                    id: searchTimer
                    interval: 300
                    onTriggered: iptv.search = searchField.text
                }
            }

            // Groepen
            ListView {
                id: groupList
                anchors.top: searchBox.bottom
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: tv.unit * 2
                anchors.bottomMargin: tv.unit * 3
                anchors.leftMargin: tv.unit * 2
                anchors.rightMargin: tv.unit * 2
                clip: true
                keyNavigationEnabled: true
                highlightMoveDuration: 120
                model: iptv.groups

                delegate: Rectangle {
                    id: groupRow
                    required property int index
                    required property string modelData
                    readonly property bool focused: groupList.activeFocus && groupList.currentIndex === index
                    readonly property bool chosen: iptv.search === "" && iptv.group === modelData
                    width: groupList.width
                    height: tv.unit * 5.6
                    radius: height / 2
                    color: focused ? "#e8eaed" : chosen ? "#2a2d33" : "transparent"
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: tv.unit * 2.2
                        anchors.rightMargin: tv.unit * 1.5
                        elide: Text.ElideRight
                        color: groupRow.focused ? "#111318" : "white"
                        font.pixelSize: (tv.unit * 2.3) * appModel.fontScale
                        font.weight: groupRow.chosen ? Font.DemiBold : Font.Normal
                        text: (groupRow.index === 0 ? "★  " : "") + groupRow.modelData
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            groupList.currentIndex = groupRow.index
                            groupList.choose(groupRow.index)
                        }
                    }
                }

                function choose(index) {
                    searchField.text = ""
                    iptv.search = ""
                    iptv.group = model[index]
                    grid.currentIndex = 0
                    grid.forceActiveFocus()
                }

                Keys.onReturnPressed: choose(currentIndex)
                Keys.onEnterPressed: choose(currentIndex)
                Keys.onRightPressed: choose(currentIndex)
                Keys.onUpPressed: (event) => {
                    if (currentIndex === 0) {
                        searchField.forceActiveFocus()
                    } else {
                        event.accepted = false
                    }
                }
            }
        }

        // Knoppen rechtsboven
        Row {
            id: buttons
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: tv.unit * 3
            spacing: tv.unit * 1.2
            FocusButton {
                id: gridButton
                unit: tv.unit
                text: "Gids"
                onClicked: tv.openGrid()
                KeyNavigation.right: recordingsButton
                KeyNavigation.down: grid
            }
            FocusButton {
                id: recordingsButton
                unit: tv.unit
                text: recorder.recording ? "●  Opnames" : "Opnames"
                onClicked: recordPanel.open(iptv.channelAt(Math.max(0, grid.currentIndex)), recordingsButton)
                KeyNavigation.left: gridButton
                KeyNavigation.right: sourcesButton
                KeyNavigation.down: grid
            }
            FocusButton {
                id: sourcesButton
                unit: tv.unit
                text: "Bronnen"
                onClicked: sources.open()
                KeyNavigation.left: recordingsButton
                KeyNavigation.right: reloadButton
                KeyNavigation.down: grid
            }
            FocusButton {
                id: reloadButton
                unit: tv.unit
                text: "Vernieuwen"
                onClicked: iptv.reload()
                KeyNavigation.left: sourcesButton
                KeyNavigation.right: backButton
                KeyNavigation.down: grid
            }
            FocusButton {
                id: backButton
                unit: tv.unit
                text: "Terug"
                onClicked: tv.close()
                KeyNavigation.left: reloadButton
                KeyNavigation.down: grid
            }
        }

        Text {
            id: heading
            anchors.left: sidebar.right
            anchors.leftMargin: tv.unit * 4
            anchors.verticalCenter: buttons.verticalCenter
            width: buttons.x - x - tv.unit * 2
            elide: Text.ElideRight
            color: "white"
            font.pixelSize: (tv.unit * 3.4) * appModel.fontScale
            font.weight: Font.DemiBold
            text: iptv.search !== "" ? "Zoeken: " + iptv.search : iptv.group
        }
        Text {
            id: statusLine
            anchors.left: heading.left
            anchors.top: heading.bottom
            anchors.topMargin: tv.unit * 0.6
            width: parent.width - x - tv.unit * 3
            elide: Text.ElideRight
            color: "#9fb4d0"
            font.pixelSize: (tv.unit * 2) * appModel.fontScale
            text: iptv.status + (iptv.count > 0 ? "  ·  " + iptv.count + " zenders" : "")
                  + (gamepad.connectedCount > 0 ? "  ·  Ⓧ favoriet  ·  Ⓨ tv-gids  ·  RB opnemen" : "  ·  F2 of rechtermuisknop: favoriet  ·  I: tv-gids  ·  G: gids alle zenders  ·  R: opnemen")
        }

        GridView {
            id: grid
            readonly property real pad: tv.unit * 2
            readonly property int columns: Math.max(3, Math.round(width / (tv.unit * 38)))
            anchors.top: statusLine.bottom
            anchors.bottom: parent.bottom
            anchors.left: sidebar.right
            anchors.right: parent.right
            anchors.topMargin: tv.unit * 2
            anchors.leftMargin: tv.unit * 1.5
            anchors.rightMargin: tv.unit * 1.5
            leftMargin: pad
            rightMargin: pad
            topMargin: pad
            bottomMargin: pad
            cellWidth: Math.floor((width - pad * 2) / columns)
            cellHeight: Math.floor(cellWidth * 0.42)
            clip: true
            focus: true
            keyNavigationEnabled: true
            highlightMoveDuration: 120
            model: iptv

            delegate: BannerTile {
                width: grid.cellWidth
                height: grid.cellHeight
                selected: grid.activeFocus && grid.currentIndex === index
                onActivated: {
                    grid.currentIndex = index
                    tv.play(index)
                }
                onHovered: {
                    if (!sources.visible) {
                        grid.currentIndex = index
                        grid.forceActiveFocus()
                    }
                }
                onMenuRequested: {
                    grid.currentIndex = index
                    tv.toggleFavorite(index)
                }
            }

            Keys.onReturnPressed: tv.play(currentIndex)
            Keys.onEnterPressed: tv.play(currentIndex)
            Keys.onMenuPressed: tv.toggleFavorite(currentIndex)
            Keys.onPressed: (event) => {
                if (event.text.length === 1 && event.text >= "0" && event.text <= "9") {
                    tv.digit(event.text)
                    event.accepted = true
                } else if (event.key === Qt.Key_F2) {
                    tv.toggleFavorite(currentIndex)
                    event.accepted = true
                } else if (event.key === Qt.Key_I) {
                    tv.openGuide(currentIndex)
                    event.accepted = true
                } else if (event.key === Qt.Key_G) {
                    tv.openGrid()
                    event.accepted = true
                } else if (event.key === Qt.Key_R) {
                    tv.openRecord(currentIndex)
                    event.accepted = true
                }
            }
            Keys.onLeftPressed: (event) => {
                if (currentIndex % columns === 0) {
                    groupList.forceActiveFocus()
                } else {
                    event.accepted = false
                }
            }
            Keys.onUpPressed: (event) => {
                if (currentIndex < columns) {
                    gridButton.forceActiveFocus()
                } else {
                    event.accepted = false
                }
            }

            Text {
                anchors.centerIn: parent
                width: parent.width * 0.8
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: iptv.count === 0
                color: "#9fb4d0"
                font.pixelSize: (tv.unit * 2.6) * appModel.fontScale
                text: iptv.busy ? "Zenders laden…"
                      : iptv.sources.length === 0 ? "Nog geen bron: kies Bronnen om een M3U-lijst of Xtream-account toe te voegen"
                      : iptv.search !== "" ? "Geen zender gevonden"
                      : iptv.group === "Favorieten" ? "Nog geen favorieten: druk F2 of X op een zender"
                      : "Geen zenders in deze groep"
            }
        }
    }

    // =====================================================================
    // Speler
    // =====================================================================
    FocusScope {
        id: playerView
        anchors.fill: parent
        visible: tv.playing

        Rectangle {
            anchors.fill: parent
            color: "black"
        }

        Loader {
            id: playerLoader
            anchors.fill: parent
            active: tv.playing
            sourceComponent: Item {
                property alias mediaPlayer: mediaPlayer
                MediaPlayer {
                    id: mediaPlayer
                    audioOutput: AudioOutput {}
                    videoOutput: video
                    onErrorOccurred: (error, errorString) => {
                        tv.errorText = errorString !== "" ? errorString : "Deze zender kan niet worden afgespeeld"
                        console.warn("IPTV play error:", errorString, tv.channel.url)
                        // Meteen een uitweg aanbieden: knop "Volgende zender" krijgt focus
                        if (tv.playing) errorNext.forceActiveFocus()
                    }
                    onMediaStatusChanged: {
                        if (mediaStatus === MediaPlayer.BufferedMedia) {
                            console.info("IPTV playing:", tv.channel.name, String(source).startsWith("udp://") ? "(relay)" : "")
                        }
                    }
                }
                VideoOutput {
                    id: video
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectFit
                }
            }
        }

        // Laden / fout
        Column {
            anchors.centerIn: parent
            spacing: tv.unit * 1.5
            visible: tv.errorText !== "" || (tv.player !== null && (tv.player.mediaStatus === MediaPlayer.LoadingMedia
                     || tv.player.mediaStatus === MediaPlayer.StalledMedia
                     || (tv.player.mediaStatus === MediaPlayer.BufferingMedia && !tv.player.hasVideo)))
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: "white"
                font.pixelSize: (tv.unit * 3.4) * appModel.fontScale
                font.weight: Font.DemiBold
                text: tv.errorText !== "" ? "Deze zender is nu niet te zien" : "Laden…"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, tv.width * 0.7)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: tv.errorText !== ""
                color: "#d5d8dc"
                font.pixelSize: (tv.unit * 2.4) * appModel.fontScale
                text: "Soms zendt een zender even niet uit, of is hij alleen in een ander land te zien."
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: tv.errorText !== ""
                spacing: tv.unit * 1.5
                FocusButton {
                    id: errorNext
                    unit: tv.unit
                    text: "Volgende zender"
                    onClicked: tv.zap(1)
                    KeyNavigation.right: errorExternal
                }
                FocusButton {
                    id: errorExternal
                    unit: tv.unit
                    text: "Probeer in andere speler"
                    onClicked: if (iptv.openExternal(tv.playingRow)) tv.stop()
                    KeyNavigation.left: errorNext
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: tv.errorText !== ""
                color: "#a8acb3"
                font.pixelSize: (tv.unit * 1.7) * appModel.fontScale
                text: "Technische melding: " + tv.errorText
            }
        }

        // Zenderbalk onderaan, verschijnt bij wisselen of Enter
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: tv.unit * 26
            opacity: infoTimer.running || tv.pinInfo || tv.errorText !== "" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 250 } }
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#000b0c0f" }
                GradientStop { position: 0.5; color: "#c00b0c0f" }
                GradientStop { position: 1.0; color: "#f00b0c0f" }
            }

            Row {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: tv.unit * 5
                anchors.bottomMargin: tv.unit * 4
                spacing: tv.unit * 3

                Rectangle {
                    width: tv.unit * 12
                    height: tv.unit * 9
                    radius: tv.unit
                    color: "#22252b"
                    Image {
                        anchors.fill: parent
                        anchors.margins: tv.unit
                        source: tv.channel.logo || ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: tv.unit * 0.6
                    width: tv.width - tv.unit * 25
                    Text {
                        color: "white"
                        font.pixelSize: (tv.unit * 4) * appModel.fontScale
                        font.weight: Font.DemiBold
                        text: (tv.channel.number || "") + "   " + (tv.channel.name || "")
                    }
                    // Gids: nu en straks
                    Row {
                        spacing: tv.unit * 1.5
                        visible: !!tv.nowNext.nowTitle
                        Text {
                            color: "#ffb74d"
                            font.pixelSize: (tv.unit * 2.4) * appModel.fontScale
                            font.weight: Font.DemiBold
                            text: "NU"
                        }
                        Text {
                            color: "white"
                            font.pixelSize: (tv.unit * 2.6) * appModel.fontScale
                            text: (tv.nowNext.nowTime || "") + "   " + (tv.nowNext.nowTitle || "")
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, tv.width * 0.6)
                        }
                    }
                    Rectangle {
                        visible: !!tv.nowNext.nowTitle
                        width: tv.unit * 40
                        height: tv.unit * 0.5
                        radius: height / 2
                        color: "#40ffffff"
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, tv.nowNext.nowProgress || 0))
                            height: parent.height
                            radius: height / 2
                            color: "#ffb74d"
                        }
                    }
                    Text {
                        visible: !!tv.nowNext.nextTitle
                        color: "#b0b4bb"
                        font.pixelSize: (tv.unit * 2.2) * appModel.fontScale
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, tv.width * 0.6)
                        text: "Straks  " + (tv.nowNext.nextTime || "") + "   " + (tv.nowNext.nextTitle || "")
                    }
                    Text {
                        visible: !tv.nowNext.nowTitle && !tv.nowNext.nextTitle
                        color: "#a8acb3"
                        font.pixelSize: (tv.unit * 2.2) * appModel.fontScale
                        text: iptv.epgStatus === "Gids laden…" ? "Gids laden…" : "Geen gidsinformatie voor deze zender"
                    }
                    HintBar {
                        unit: tv.unit * 0.85
                        items: [
                            { pad: "✛", key: "↑ ↓", label: "Andere zender" },
                            { pad: "A", key: "Enter", label: "Tv-gids" },
                            { pad: "RB", key: "R", label: "Opnemen" },
                            { pad: "X", key: "F2", label: "Favoriet" },
                            { pad: "", key: "0", label: "Vorige zender" },
                            { pad: "", key: "G", label: "Gids" },
                            { pad: "B", key: "Esc", label: "Terug" }
                        ]
                    }
                }
            }
        }
        Timer { id: infoTimer; interval: 2000 }

        Keys.onEscapePressed: tv.stop()
        Keys.onBackPressed: tv.stop()
        Keys.onUpPressed: tv.zap(-1)
        Keys.onDownPressed: tv.zap(1)
        Keys.onLeftPressed: tv.showInfo()
        Keys.onRightPressed: tv.showInfo()
        Keys.onReturnPressed: tv.openGuide(tv.playingRow)
        Keys.onEnterPressed: tv.openGuide(tv.playingRow)
        Keys.onMenuPressed: tv.toggleFavorite(tv.playingRow)
        Keys.onPressed: (event) => {
            if (event.text.length === 1 && event.text >= "0" && event.text <= "9") {
                tv.digit(event.text)
                event.accepted = true
            } else if (event.key === Qt.Key_F2) {
                tv.toggleFavorite(tv.playingRow)
                event.accepted = true
            } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_ChannelUp) {
                tv.zap(-1)
                event.accepted = true
            } else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_ChannelDown) {
                tv.zap(1)
                event.accepted = true
            } else if (event.key === Qt.Key_Backspace) {
                tv.previousChannel()
                event.accepted = true
            } else if (event.key === Qt.Key_G) {
                tv.openGrid()
                event.accepted = true
            } else if (event.key === Qt.Key_I) {
                tv.openGuide(tv.playingRow)
                event.accepted = true
            } else if (event.key === Qt.Key_R) {
                tv.openRecord(tv.playingRow)
                event.accepted = true
            } else if (event.key === Qt.Key_E) {
                if (iptv.openExternal(tv.playingRow)) {
                    tv.stop()
                }
                event.accepted = true
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: tv.showInfo()
            onDoubleClicked: tv.stop()
        }
    }

    // --- Korte melding ---
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: tv.unit * 4
        width: message.implicitWidth + tv.unit * 6
        height: tv.unit * 7
        radius: height / 2
        color: "#e6000000"
        opacity: messageTimer.running ? 1 : 0
        visible: opacity > 0
        z: 10
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Text {
            id: message
            anchors.centerIn: parent
            color: "white"
            font.pixelSize: (tv.unit * 2.6) * appModel.fontScale
        }
    }
    Timer { id: messageTimer; interval: 2500 }

    // Elke minuut "nu" bijwerken
    Timer {
        id: epgClock
        property int tick: 0
        interval: 60000
        repeat: true
        running: tv.visible
        onTriggered: tick++
    }

    EpgPanel {
        id: guidePanel
        unit: tv.unit
    }

    GuideGrid {
        id: guideGrid
        onWatchRequested: (row) => tv.play(row)
    }

    RecordPanel {
        id: recordPanel
        unit: tv.unit
    }

    // Opname-indicator linksboven, zolang er opgenomen wordt, met stopknop (vierkantje)
    Rectangle {
        id: recIndicator
        visible: recorder.recording && tv.visible && !recordPanel.visible
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: tv.unit * 3
        z: 30
        width: recRow.implicitWidth + tv.unit * 3
        height: tv.unit * 5.5
        radius: height / 2
        color: "#cc000000"
        Row {
            id: recRow
            anchors.centerIn: parent
            spacing: tv.unit
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: tv.unit * 1.6; height: width; radius: width / 2
                color: "#e53935"
                SequentialAnimation on opacity {
                    running: recorder.recording; loops: Animation.Infinite
                    NumberAnimation { to: 0.2; duration: 600 } NumberAnimation { to: 1; duration: 600 }
                }
            }
            Text {
                id: recText
                color: "white"
                font.pixelSize: (tv.unit * 2.3) * appModel.fontScale
                text: "REC  " + recorder.channel + "  " + recordPanel.fmtTime(recorder.elapsedSeconds)
            }
            // Stopknop: wit vierkantje; muis erop = "Opname stoppen"
            Rectangle {
                id: stopButton
                anchors.verticalCenter: parent.verticalCenter
                width: tv.unit * 3.6; height: width; radius: tv.unit * 0.6
                color: stopMouse.containsMouse ? "#e53935" : "#33ffffff"
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.42; height: width; radius: tv.unit * 0.2
                    color: "white"
                }
                MouseArea {
                    id: stopMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { recorder.stop(); console.info("Recording stopped via stop button") }
                }
            }
        }
        // Uitleg bij de muis
        Rectangle {
            visible: stopMouse.containsMouse
            anchors.top: parent.bottom
            anchors.topMargin: tv.unit * 0.8
            anchors.right: parent.right
            width: tipText.implicitWidth + tv.unit * 2
            height: tv.unit * 4
            radius: tv.unit * 0.8
            color: "#ee16181d"
            Text {
                id: tipText
                anchors.centerIn: parent
                text: "Opname stoppen"
                color: "white"
                font.pixelSize: (tv.unit * 2) * appModel.fontScale
            }
        }
    }

    // Getypt zendernummer, groot rechtsboven
    Rectangle {
        visible: tv.numberEntry !== "" && tv.visible
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: tv.unit * 4
        z: 40
        width: Math.max(tv.unit * 14, numberText.implicitWidth + tv.unit * 4)
        height: tv.unit * 12
        radius: tv.unit * 1.5
        color: "#e016181d"
        Column {
            anchors.centerIn: parent
            Text {
                id: numberText
                anchors.horizontalCenter: parent.horizontalCenter
                text: tv.numberEntry
                color: "white"
                font.pixelSize: tv.unit * 6
                font.weight: Font.Bold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                readonly property int n: parseInt(tv.numberEntry) - 1
                text: n >= 0 && n < iptv.count ? iptv.channelAt(n).name : "—"
                color: "#c9ccd1"
                font.pixelSize: tv.unit * 2 * appModel.fontScale
            }
        }
    }

    IptvSources {
        id: sources
        onClosed: grid.forceActiveFocus()
    }
}
