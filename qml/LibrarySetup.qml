// Eerste gebruik (en later via "Mappen en sleutel"): mappen voor films en series
// kiezen, en optioneel een TMDB-sleutel invullen.
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Dialogs

FocusScope {
    id: setup

    readonly property real unit: height / 100
    property string moviesPath
    property string showsPath
    property bool firstRun: false
    signal saved()
    signal cancelled()

    anchors.fill: parent
    visible: false
    z: 100

    function open(isFirstRun) {
        firstRun = isFirstRun
        moviesPath = library.moviesFolder
        showsPath = library.showsFolder
        keyField.text = library.apiKey
        warning.text = ""
        visible = true
        moviesButton.forceActiveFocus()
    }

    function close() {
        visible = false
    }

    function save() {
        if (moviesPath === "" && showsPath === "") {
            warning.text = "Kies minstens één map."
            moviesButton.forceActiveFocus()
            return
        }
        library.configure(moviesPath, showsPath, keyField.text)
        close()
        saved()
    }

    Keys.onEscapePressed: {
        close()
        cancelled()
    }

    FolderDialog {
        id: moviesDialog
        title: "Map met films kiezen"
        onAccepted: setup.moviesPath = library.localPath(selectedFolder)
    }
    FolderDialog {
        id: showsDialog
        title: "Map met series kiezen"
        onAccepted: setup.showsPath = library.localPath(selectedFolder)
    }

    Rectangle {
        anchors.fill: parent
        color: "#d8000000"
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, setup.unit * 125)
        height: content.height + setup.unit * 8
        radius: setup.unit * 2
        color: "#1b1d22"
        border.color: "#33ffffff"
        border.width: 1

        Column {
            id: content
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: setup.unit * 4
            spacing: setup.unit * 1.6

            Text {
                color: "white"
                font.pixelSize: setup.unit * 4
                font.weight: Font.DemiBold
                text: setup.firstRun ? "Bibliotheek instellen" : "Mappen en sleutel"
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                color: "#c4c7cc"
                font.pixelSize: setup.unit * 2.2
                text: "Kies de mappen met je films en series. Bigscreen zoekt daarin de video's en haalt titel, "
                      + "beschrijving, poster, achtergrond en cast op, zoals Kodi dat doet. Zet elke serie in een eigen "
                      + "map (bijvoorbeeld Series\\Westworld (2016)) en noem afleveringen S01E01, S01E02 enzovoort."
            }

            // Films
            Text { color: "#9fb4d0"; font.pixelSize: setup.unit * 2.2; text: "Map met films" }
            Row {
                spacing: setup.unit * 1.5
                Rectangle {
                    width: content.width - moviesButton.width - parent.spacing
                    height: setup.unit * 6
                    radius: setup.unit
                    color: "#0f1115"
                    Text {
                        anchors.fill: parent
                        anchors.margins: setup.unit * 1.5
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideMiddle
                        color: setup.moviesPath !== "" ? "white" : "#7d8188"
                        font.pixelSize: setup.unit * 2.3
                        text: setup.moviesPath !== "" ? setup.moviesPath : "Nog niet gekozen (mag leeg blijven)"
                    }
                }
                FocusButton {
                    id: moviesButton
                    unit: setup.unit
                    text: "Kiezen…"
                    onClicked: moviesDialog.open()
                    KeyNavigation.down: showsButton
                }
            }

            // Series
            Text { color: "#9fb4d0"; font.pixelSize: setup.unit * 2.2; text: "Map met series" }
            Row {
                spacing: setup.unit * 1.5
                Rectangle {
                    width: content.width - showsButton.width - parent.spacing
                    height: setup.unit * 6
                    radius: setup.unit
                    color: "#0f1115"
                    Text {
                        anchors.fill: parent
                        anchors.margins: setup.unit * 1.5
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideMiddle
                        color: setup.showsPath !== "" ? "white" : "#7d8188"
                        font.pixelSize: setup.unit * 2.3
                        text: setup.showsPath !== "" ? setup.showsPath : "Nog niet gekozen (mag leeg blijven)"
                    }
                }
                FocusButton {
                    id: showsButton
                    unit: setup.unit
                    text: "Kiezen…"
                    onClicked: showsDialog.open()
                    KeyNavigation.up: moviesButton
                    KeyNavigation.down: keyField
                }
            }

            // TMDB-sleutel
            Text { color: "#9fb4d0"; font.pixelSize: setup.unit * 2.2; text: "TMDB API-sleutel (gratis, nodig voor films)" }
            Rectangle {
                width: parent.width
                height: setup.unit * 6
                radius: setup.unit
                color: "#0f1115"
                border.width: keyField.activeFocus ? 3 : 1
                border.color: keyField.activeFocus ? "#e8eaed" : "#33ffffff"
                TextInput {
                    id: keyField
                    anchors.fill: parent
                    anchors.margins: setup.unit * 1.5
                    verticalAlignment: TextInput.AlignVCenter
                    color: "white"
                    font.pixelSize: setup.unit * 2.3
                    clip: true
                    selectByMouse: true
                    KeyNavigation.up: showsButton
                    KeyNavigation.down: saveButton
                    onAccepted: setup.save()
                }
                Text {
                    anchors.fill: keyField
                    verticalAlignment: Text.AlignVCenter
                    visible: keyField.text === "" && !keyField.activeFocus
                    color: "#7d8188"
                    font.pixelSize: setup.unit * 2.3
                    text: "Plak hier je sleutel of token"
                }
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                color: "#9a9ea6"
                font.pixelSize: setup.unit * 1.9
                text: "Sleutel aanvragen: maak een gratis account op themoviedb.org en ga naar Instellingen → API. "
                      + "Zonder sleutel komen series van TVmaze en tonen films alleen hun titel. "
                      + "Dit product gebruikt de TMDB API, maar is niet door TMDB goedgekeurd of gecertificeerd."
            }

            Text {
                id: warning
                visible: text !== ""
                color: "#ff8a80"
                font.pixelSize: setup.unit * 2.2
            }

            Row {
                spacing: setup.unit * 1.5
                FocusButton {
                    id: saveButton
                    unit: setup.unit
                    text: "Opslaan en zoeken"
                    onClicked: setup.save()
                    KeyNavigation.up: keyField
                    KeyNavigation.right: cancelButton
                }
                FocusButton {
                    id: cancelButton
                    unit: setup.unit
                    text: "Annuleren"
                    onClicked: {
                        setup.close()
                        setup.cancelled()
                    }
                    KeyNavigation.up: keyField
                    KeyNavigation.left: saveButton
                }
            }
        }
    }
}
