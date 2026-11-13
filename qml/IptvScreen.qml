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
    property alias guideStart: guidePanel.startIndex
    // Gids van de zender die nu speelt; ververst als er nieuwe gidsgegevens zijn
    readonly property var nowNext: (iptv.epgRevision, epgClock.tick, playingRow >= 0 ? iptv.nowNext(playingRow) : ({}))
    // De speler bestaat alleen tijdens het kijken (snellere start, decoder weer vrij)
    readonly property var player: playerLoader.item ? playerLoader.item.mediaPlayer : null

    anchors.fill: parent
    visible: false
    z: 50

    function open(focusItem) {
        returnFocusTo = focusItem
        visible = true
        grid.forceActiveFocus()
        if (iptv.sources.length === 0) {
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

    function play(row) {
        const ch = iptv.channelAt(row)
        if (!ch.url) {
            return
        }
        playingRow = row
        channel = ch
        errorText = ""
        playing = true
        if (player) {
            player.stop()
            player.source = ch.url
            player.play()
        }
        iptv.requestEpg(row)
        showInfo()
        playerView.forceActiveFocus()
        if (autoGuide) {
            autoGuide = false
            guideTestTimer.start()
        }
    }
    Timer { id: guideTestTimer; interval: 6000; onTriggered: tv.openGuide(tv.playingRow) }

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
                font.pixelSize: tv.unit * 3.6
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
                    font.pixelSize: tv.unit * 2.3
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
                        color: "#7d8188"
                        font.pixelSize: tv.unit * 2.3
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
                        font.pixelSize: tv.unit * 2.3
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
                id: sourcesButton
                unit: tv.unit
                text: "Bronnen"
                onClicked: sources.open()
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
            font.pixelSize: tv.unit * 3.4
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
            font.pixelSize: tv.unit * 2
            text: iptv.status + (iptv.count > 0 ? "  ·  " + iptv.count + " in deze lijst" : "")
                  + "  ·  F2, rechtermuisknop of X: favoriet"
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
                if (event.key === Qt.Key_F2) {
                    tv.toggleFavorite(currentIndex)
                    event.accepted = true
                } else if (event.key === Qt.Key_I) {
                    tv.openGuide(currentIndex)
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
                    sourcesButton.forceActiveFocus()
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
                font.pixelSize: tv.unit * 2.6
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
                    }
                    onMediaStatusChanged: {
                        if (mediaStatus === MediaPlayer.BufferedMedia) {
                            console.info("IPTV playing:", tv.channel.name)
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
                font.pixelSize: tv.unit * 3
                text: tv.errorText !== "" ? "Afspelen lukt niet" : "Laden…"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, tv.width * 0.7)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: tv.errorText !== ""
                color: "#b0b4bb"
                font.pixelSize: tv.unit * 2.2
                text: tv.errorText + "\nDruk E om de zender in een externe speler te openen."
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
                        font.pixelSize: tv.unit * 4
                        font.weight: Font.DemiBold
                        text: (tv.channel.number || "") + "   " + (tv.channel.name || "")
                    }
                    // Gids: nu en straks
                    Row {
                        spacing: tv.unit * 1.5
                        visible: !!tv.nowNext.nowTitle
                        Text {
                            color: "#ffb74d"
                            font.pixelSize: tv.unit * 2.4
                            font.weight: Font.DemiBold
                            text: "NU"
                        }
                        Text {
                            color: "white"
                            font.pixelSize: tv.unit * 2.6
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
                        font.pixelSize: tv.unit * 2.2
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, tv.width * 0.6)
                        text: "Straks  " + (tv.nowNext.nextTime || "") + "   " + (tv.nowNext.nextTitle || "")
                    }
                    Text {
                        visible: !tv.nowNext.nowTitle && !tv.nowNext.nextTitle
                        color: "#80848b"
                        font.pixelSize: tv.unit * 2.2
                        text: iptv.epgStatus === "Gids laden…" ? "Gids laden…" : "Geen gidsinformatie voor deze zender"
                    }
                    Text {
                        color: "#80848b"
                        font.pixelSize: tv.unit * 1.9
                        text: (tv.channel.group || "") + "    ·    ↑ ↓ zender   ·   OK / I / Y gids   ·   Esc / B terug   ·   F2 / X favoriet   ·   E externe speler"
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
            if (event.key === Qt.Key_F2) {
                tv.toggleFavorite(tv.playingRow)
                event.accepted = true
            } else if (event.key === Qt.Key_I) {
                tv.openGuide(tv.playingRow)
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
            font.pixelSize: tv.unit * 2.6
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

    IptvSources {
        id: sources
        onClosed: grid.forceActiveFocus()
    }
}
