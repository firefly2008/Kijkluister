// Radio luisteren in Kijkluister zelf: schermvullend, met het logo van de zender groot in beeld.
// Links/rechts: andere zender. Omhoog/omlaag: volume. Enter: pauze.
// Esc/B: terug naar het startscherm, de radio speelt door. X/Menu/Delete: stoppen. Y: slaaptimer.
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtMultimedia

FocusScope {
    id: radioPlayer

    readonly property real unit: height / 100
    property Item returnFocusTo: null
    property int row: -1
    property int streamIndex: 0
    property string errorText: ""
    property string nowPlaying: ""
    readonly property string accent: row >= 0 ? radio.accentAt(row) : "#22252b"
    readonly property string logo: row >= 0 ? radio.iconAt(row + radio.revision * 0) : ""
    readonly property bool loading: errorText === "" && (player.mediaStatus === MediaPlayer.LoadingMedia
                                     || player.mediaStatus === MediaPlayer.StalledMedia
                                     || player.mediaStatus === MediaPlayer.BufferingMedia
                                     || (player.playbackState === MediaPlayer.PlayingState && player.mediaStatus === MediaPlayer.NoMedia))
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState && !loading && errorText === ""
    readonly property bool paused: player.playbackState === MediaPlayer.PausedState
    // Speelt (of laadt) er een zender, ook als het scherm dicht is
    readonly property bool active: row >= 0 && player.playbackState !== MediaPlayer.StoppedState
    readonly property bool inBackground: active && !visible
    signal sleepRequested()
    // Nachtmodus: radio zachter
    property real maxVolume: 1.0
    onMaxVolumeChanged: if (audio.volume > maxVolume) audio.volume = maxVolume
    property string sleepText: ""

    anchors.fill: parent
    visible: false
    z: 60

    onActiveFocusChanged: {
        if (visible && !activeFocus) {
            Qt.callLater(() => { if (radioPlayer.visible && !radioPlayer.activeFocus && !menu.visible) radioPlayer.forceActiveFocus() })
        }
    }

    function open(stationRow, focusItem) {
        returnFocusTo = focusItem
        visible = true
        forceActiveFocus()
        if (stationRow !== row || !active) {
            tune(stationRow)
        }
    }

    // Weer tonen terwijl hij op de achtergrond speelt
    function show(focusItem) {
        returnFocusTo = focusItem
        visible = true
        forceActiveFocus()
    }

    // Terug naar het startscherm; de radio speelt door
    function close() {
        if (!active) {
            stopPlayback()
            return
        }
        console.info("Radio in background", radio.nameAt(row))
        visible = false
        if (returnFocusTo) {
            returnFocusTo.forceActiveFocus()
        }
    }

    function stopPlayback() {
        console.info("Radio closed")
        stallTimer.stop()
        player.stop()
        player.source = ""
        const wasVisible = visible
        visible = false
        row = -1
        if (wasVisible && returnFocusTo) {
            returnFocusTo.forceActiveFocus()
        }
    }

    function tune(stationRow) {
        row = radio.isStation(stationRow) ? stationRow : radio.nextStation(stationRow, 1)
        streamIndex = 0
        playStream()
    }

    function playStream() {
        errorText = ""
        nowPlaying = ""
        const streams = radio.streamsAt(row)
        console.info("Radio play", radio.nameAt(row), streams[streamIndex])
        player.stop()
        player.source = streams[streamIndex]
        player.play()
        stallTimer.restart()
    }

    // Lukt een adres niet: het volgende proberen, daarna een melding
    function tryNext(reason) {
        const streams = radio.streamsAt(row)
        console.info("Radio stream failed", streams[streamIndex], reason)
        if (streamIndex + 1 < streams.length) {
            streamIndex += 1
            playStream()
        } else {
            player.stop()
            errorText = radio.nameAt(row) + " is nu niet te beluisteren."
        }
    }

    function togglePause() {
        if (errorText !== "") {
            streamIndex = 0
            playStream()
        } else if (player.playbackState === MediaPlayer.PlayingState) {
            player.pause()
        } else {
            // Live radio: na een pauze weer bij "nu" beginnen
            playStream()
        }
    }

    function changeVolume(delta) {
        audio.volume = Math.max(0, Math.min(maxVolume, Math.round((audio.volume + delta) * 20) / 20))
        volumeFlash.restart()
    }

    MediaPlayer {
        id: player
        audioOutput: AudioOutput {
            id: audio
            volume: 0.8
        }
        onErrorOccurred: (error, message) => radioPlayer.tryNext(message)
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.BufferedMedia) {
                stallTimer.stop()
                console.info("Radio playing", radio.nameAt(radioPlayer.row), source)
            } else if (mediaStatus === MediaPlayer.InvalidMedia) {
                radioPlayer.tryNext("invalid media")
            }
        }
        onMetaDataChanged: {
            const title = metaData.stringValue(MediaMetaData.Title)
            const artist = metaData.stringValue(MediaMetaData.ContributingArtist)
            const text = (artist && title) ? artist + " – " + title : (title || "")
            // Sommige zenders sturen hun eigen naam of een slogan als titel
            radioPlayer.nowPlaying = text.toLowerCase().indexOf(radio.nameAt(radioPlayer.row).toLowerCase()) >= 0 ? "" : text
        }
    }

    // Blijft het te lang laden: volgend adres
    Timer {
        id: stallTimer
        interval: 15000
        onTriggered: if (radioPlayer.visible && radioPlayer.loading) radioPlayer.tryNext("timeout")
    }

    Keys.onLeftPressed: tune(radio.nextStation(row, -1))
    Keys.onRightPressed: tune(radio.nextStation(row, 1))
    Keys.onUpPressed: changeVolume(0.05)
    Keys.onDownPressed: changeVolume(-0.05)
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back || event.key === Qt.Key_Backspace) {
            close()
            event.accepted = true
        } else if (event.key === Qt.Key_Menu || event.key === Qt.Key_Delete || event.key === Qt.Key_X || event.key === Qt.Key_MediaStop) {
            stopPlayback()
            event.accepted = true
        } else if (event.key === Qt.Key_I || event.key === Qt.Key_T) {
            sleepRequested()
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space
                   || event.key === Qt.Key_MediaPlay || event.key === Qt.Key_MediaTogglePlayPause) {
            togglePause()
            event.accepted = true
        } else if (event.key === Qt.Key_MediaNext || event.key === Qt.Key_PageDown) {
            tune(radio.nextStation(row, 1))
            event.accepted = true
        } else if (event.key === Qt.Key_MediaPrevious || event.key === Qt.Key_PageUp) {
            tune(radio.nextStation(row, -1))
            event.accepted = true
        } else if (event.key === Qt.Key_VolumeUp) {
            changeVolume(0.05)
            event.accepted = true
        } else if (event.key === Qt.Key_VolumeDown) {
            changeVolume(-0.05)
            event.accepted = true
        }
    }

    // Achtergrond: de kleur van de zender, van boven naar beneden donkerder
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.darker(radioPlayer.accent, 1.1) }
            GradientStop { position: 0.75; color: "#0b0c0f" }
        }
        Behavior on gradient { enabled: false }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: radioPlayer.forceActiveFocus()
    }

    // Titel linksboven
    Text {
        x: radioPlayer.unit * 4
        y: radioPlayer.unit * 4
        text: "Radio"
        color: "#ffffff"
        font.pixelSize: radioPlayer.unit * 4 * appModel.fontScale
        font.weight: Font.DemiBold
    }

    // Midden: logo, naam, status
    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -radioPlayer.unit * 6
        spacing: radioPlayer.unit * 2.4

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: radioPlayer.unit * 26
            height: width
            radius: width * 0.14
            color: "#ffffff"
            Image {
                anchors.centerIn: parent
                width: parent.width * 0.72
                height: width
                source: radioPlayer.logo.startsWith("glyph:") ? "" : radioPlayer.logo
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }
            Text {
                anchors.centerIn: parent
                visible: radioPlayer.logo.startsWith("glyph:")
                text: radioPlayer.logo.substring(6)
                font.family: "Segoe MDL2 Assets"
                font.pixelSize: parent.width * 0.5
                color: radioPlayer.accent
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: radioPlayer.row >= 0 ? radio.nameAt(radioPlayer.row) : ""
            color: "#ffffff"
            font.pixelSize: radioPlayer.unit * 6 * appModel.fontScale
            font.weight: Font.Bold
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: radioPlayer.row >= 0 ? radio.subtitleAt(radioPlayer.row) : ""
            color: "#c9ccd1"
            font.pixelSize: radioPlayer.unit * 2.8 * appModel.fontScale
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: radioPlayer.unit * 1.2
            height: radioPlayer.unit * 4

            // Live-stip of laad-bolletjes
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: radioPlayer.playing
                width: radioPlayer.unit * 1.6
                height: width
                radius: width / 2
                color: "#e0463e"
                SequentialAnimation on opacity {
                    running: radioPlayer.playing
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 900 }
                    NumberAnimation { to: 1.0; duration: 900 }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: radioPlayer.errorText !== "" ? "#ff8a80" : "#ffffff"
                font.pixelSize: radioPlayer.unit * 3 * appModel.fontScale
                text: radioPlayer.errorText !== "" ? radioPlayer.errorText
                    : radioPlayer.paused ? "Gepauzeerd"
                    : radioPlayer.loading ? "Verbinden…"
                    : radioPlayer.playing ? "Live" : ""
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: radioPlayer.nowPlaying !== "" && radioPlayer.playing
            width: Math.min(implicitWidth, radioPlayer.width * 0.8)
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            text: "Nu: " + radioPlayer.nowPlaying
            color: "#e6e8eb"
            font.pixelSize: radioPlayer.unit * 2.8 * appModel.fontScale
        }
    }

    // Volume: verschijnt even bij omhoog/omlaag
    Rectangle {
        id: volumeBox
        anchors.right: parent.right
        anchors.rightMargin: radioPlayer.unit * 4
        anchors.verticalCenter: parent.verticalCenter
        width: radioPlayer.unit * 6
        height: radioPlayer.unit * 34
        radius: radioPlayer.unit * 1.4
        color: "#cc16181d"
        opacity: volumeFlash.running ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: radioPlayer.unit * 5
            width: radioPlayer.unit * 1.2
            height: parent.height - radioPlayer.unit * 8
            radius: width / 2
            color: "#40ffffff"
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: parent.height * audio.volume
                radius: width / 2
                color: "#ffffff"
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: radioPlayer.unit * 1.4
            text: Math.round(audio.volume * 100) + "%"
            color: "#ffffff"
            font.pixelSize: radioPlayer.unit * 2 * appModel.fontScale
        }
        Timer { id: volumeFlash; interval: 1800 }
    }

    // Onderaan: alle zenders, de huidige uitgelicht
    Row {
        id: strip
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: hints.top
        anchors.bottomMargin: radioPlayer.unit * 3
        spacing: radioPlayer.unit * 1.6

        Repeater {
            model: radio.count
            delegate: Rectangle {
                required property int index
                readonly property string name: radio.nameAt(index)
                readonly property string iconSource: radio.iconAt(index + radio.revision * 0)
                readonly property bool current: index === radioPlayer.row
                visible: radio.isStation(index + radio.revision * 0)
                width: visible ? radioPlayer.unit * (current ? 10 : 8) * Math.min(1, 10 / Math.max(1, radio.stationCount)) : 0
                height: width
                radius: width * 0.16
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                color: "#ffffff"
                opacity: current ? 1 : 0.55
                border.width: current ? radioPlayer.unit * 0.4 : 0
                border.color: "#ffffff"
                Behavior on width { NumberAnimation { duration: 150 } }
                Image {
                    anchors.centerIn: parent
                    width: parent.width * 0.74
                    height: width
                    source: iconSource.startsWith("glyph:") ? "" : iconSource
                    fillMode: Image.PreserveAspectFit
                    mipmap: true
                }
                Text {
                    anchors.centerIn: parent
                    visible: iconSource.startsWith("glyph:")
                    width: parent.width * 0.9
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    text: name
                    color: "#16181d"
                    font.pixelSize: parent.width * 0.16
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: radioPlayer.tune(index)
                }
            }
        }
    }

    HintBar {
        id: hints
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: radioPlayer.unit * 3
        unit: radioPlayer.unit
        items: [
            { pad: "◀ ▶", key: "◀ ▶", label: "Andere zender" },
            { pad: "▲ ▼", key: "▲ ▼", label: "Volume" },
            { pad: "A", key: "Enter", label: radioPlayer.paused ? "Verder" : "Pauze" },
            { pad: "Y", key: "T", label: radioPlayer.sleepText !== "" ? "Slaaptimer: " + radioPlayer.sleepText : "Slaaptimer" },
            { pad: "B", key: "Esc", label: "Terug (speelt door)" },
            { pad: "X", key: "Del", label: "Stoppen" }
        ]
    }
}
