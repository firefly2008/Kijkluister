// Eerste gebruik (en later via "Mappen en sleutel"): mappen voor films en series
// kiezen, en optioneel een TMDB-sleutel invullen.
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Dialogs

FocusScope {
    id: setup

    readonly property real unit: height / 100
    property var moviesPaths: []
    property var showsPaths: []
    property bool firstRun: false
    signal saved()
    signal cancelled()

    anchors.fill: parent
    visible: false
    z: 100

    // De sleutel is ingebouwd en vergrendeld; na de juiste pincode is hij te zien en te wijzigen
    readonly property bool showKey: !library.keyLocked
    property bool askPin: false

    function open(isFirstRun) {
        firstRun = isFirstRun
        moviesPaths = library.moviesFolders.slice()
        showsPaths = library.showsFolders.slice()
        library.lock()
        askPin = false
        pinField.text = ""
        warning.text = ""
        visible = true
        moviesButton.forceActiveFocus()
    }

    function addPath(kind, path) {
        if (path === "") return
        const list = kind === "movies" ? moviesPaths.slice() : showsPaths.slice()
        if (list.some(p => p.toLowerCase() === path.toLowerCase())) return
        list.push(path)
        if (kind === "movies") moviesPaths = list; else showsPaths = list
    }
    function removePath(kind, index) {
        const list = kind === "movies" ? moviesPaths.slice() : showsPaths.slice()
        list.splice(index, 1)
        if (kind === "movies") moviesPaths = list; else showsPaths = list
    }

    // Lijst met gekozen mappen; F2 / X / Delete of de knop haalt er een weg
    component FolderList: Column {
        id: fl
        property string kind
        property var paths: []
        width: content.width
        spacing: setup.unit * 0.6
        Text {
            visible: fl.paths.length === 0
            color: "#a8acb3"
            font.pixelSize: (setup.unit * 2.3) * appModel.fontScale
            text: "Nog geen map gekozen (mag leeg blijven)"
        }
        Repeater {
            model: fl.paths
            delegate: Row {
                required property string modelData
                required property int index
                spacing: setup.unit * 1.5
                Rectangle {
                    width: content.width - removeButton.width - parent.spacing
                    height: setup.unit * 5.5
                    radius: setup.unit
                    color: "#0f1115"
                    Text {
                        anchors.fill: parent
                        anchors.margins: setup.unit * 1.5
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideMiddle
                        color: "white"
                        font.pixelSize: (setup.unit * 2.3) * appModel.fontScale
                        text: modelData
                    }
                }
                FocusButton {
                    id: removeButton
                    unit: setup.unit
                    text: "Weg"
                    onClicked: setup.removePath(fl.kind, index)
                }
            }
        }
    }

    function close() {
        library.lock()
        visible = false
    }

    function tryPin() {
        if (library.unlock(pinField.text)) {
            askPin = false
            warning.text = ""
            keyField.text = library.effectiveKey()
            keyField.forceActiveFocus()
        } else {
            warning.text = "Pincode klopt niet."
            pinField.text = ""
            pinField.forceActiveFocus()
        }
    }

    function save() {
        if (moviesPaths.length === 0 && showsPaths.length === 0) {
            warning.text = "Kies minstens één map."
            moviesButton.forceActiveFocus()
            return
        }
        library.configureFolders(moviesPaths, showsPaths, keyField.text)
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
        onAccepted: setup.addPath("movies", library.localPath(selectedFolder))
    }
    FolderDialog {
        id: showsDialog
        title: "Map met series kiezen"
        onAccepted: setup.addPath("shows", library.localPath(selectedFolder))
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
                font.pixelSize: (setup.unit * 4) * appModel.fontScale
                font.weight: Font.DemiBold
                text: setup.firstRun ? "Waar staan je films en series?" : "Mappen kiezen"
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                color: "#c4c7cc"
                font.pixelSize: (setup.unit * 2.2) * appModel.fontScale
                text: "Kies de map met je films en de map met je series. Meer mappen mag ook, bijvoorbeeld op een "
                      + "externe schijf. Kijkluister zoekt er zelf de titels, plaatjes en beschrijvingen bij."
            }

            // Films: een of meer mappen/locaties
            Row {
                spacing: setup.unit * 2
                Text { anchors.verticalCenter: parent.verticalCenter; color: "#9fb4d0"; font.pixelSize: (setup.unit * 2.2) * appModel.fontScale; text: "Mappen met films"}
                FocusButton {
                    id: moviesButton
                    unit: setup.unit
                    text: "+ Map toevoegen…"
                    onClicked: moviesDialog.open()
                    KeyNavigation.down: showsButton
                }
            }
            FolderList { kind: "movies"; paths: setup.moviesPaths }

            // Series: een of meer mappen/locaties
            Row {
                spacing: setup.unit * 2
                Text { anchors.verticalCenter: parent.verticalCenter; color: "#9fb4d0"; font.pixelSize: (setup.unit * 2.2) * appModel.fontScale; text: "Mappen met series"}
                FocusButton {
                    id: showsButton
                    unit: setup.unit
                    text: "+ Map toevoegen…"
                    onClicked: showsDialog.open()
                    KeyNavigation.up: moviesButton
                    KeyNavigation.down: setup.showKey ? keyField : moreButton
                }
            }
            FolderList { kind: "shows"; paths: setup.showsPaths }

            // Sleutel van TMDB: niet nodig om te beginnen, dus ingeklapt
            Row {
                visible: !setup.showKey
                spacing: setup.unit * 1.5
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#c4c7cc"
                    font.pixelSize: (setup.unit * 2.2) * appModel.fontScale
                    text: "🔒  Gegevens bij films: ingebouwde sleutel (vergrendeld)"
                }
                FocusButton {
                    id: moreButton
                    unit: setup.unit
                    visible: !setup.askPin
                    text: "Ontgrendelen…"
                    onClicked: { setup.askPin = true; pinField.forceActiveFocus() }
                    KeyNavigation.up: showsButton
                    KeyNavigation.down: saveButton
                }
                // Pincode
                Rectangle {
                    visible: setup.askPin
                    anchors.verticalCenter: parent.verticalCenter
                    width: setup.unit * 16
                    height: setup.unit * 6
                    radius: setup.unit
                    color: "#0f1115"
                    border.width: pinField.activeFocus ? 3 : 1
                    border.color: pinField.activeFocus ? "#e8eaed" : "#33ffffff"
                    TextInput {
                        id: pinField
                        anchors.fill: parent
                        anchors.margins: setup.unit * 1.5
                        verticalAlignment: TextInput.AlignVCenter
                        horizontalAlignment: TextInput.AlignHCenter
                        color: "white"
                        font.pixelSize: (setup.unit * 2.6) * appModel.fontScale
                        font.letterSpacing: setup.unit * 0.6
                        echoMode: TextInput.Password
                        maximumLength: 8
                        inputMethodHints: Qt.ImhDigitsOnly
                        validator: RegularExpressionValidator { regularExpression: /[0-9]*/ }
                        onAccepted: setup.tryPin()
                        KeyNavigation.up: showsButton
                        KeyNavigation.right: pinOk
                        KeyNavigation.down: saveButton
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: pinField.text === "" && !pinField.activeFocus
                        color: "#a8acb3"
                        font.pixelSize: (setup.unit * 2.2) * appModel.fontScale
                        text: "Pincode"
                    }
                }
                FocusButton {
                    id: pinOk
                    visible: setup.askPin
                    unit: setup.unit
                    text: "OK"
                    onClicked: setup.tryPin()
                    KeyNavigation.left: pinField
                    KeyNavigation.down: saveButton
                }
            }
            Text {
                visible: setup.showKey
                width: parent.width
                wrapMode: Text.Wrap
                color: "#9fb4d0"
                font.pixelSize: (setup.unit * 2.2) * appModel.fontScale
                text: "Sleutel van TMDB (ontgrendeld). Leeg laten = de ingebouwde sleutel gebruiken."
            }
            Rectangle {
                visible: setup.showKey
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
                    font.pixelSize: (setup.unit * 2.3) * appModel.fontScale
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
                    color: "#a8acb3"
                    font.pixelSize: (setup.unit * 2.3) * appModel.fontScale
                    text: "Plak hier je sleutel of token"
                }
            }
            Text {
                visible: setup.showKey
                width: parent.width
                wrapMode: Text.Wrap
                color: "#b0b4bb"
                font.pixelSize: (setup.unit * 1.9) * appModel.fontScale
                text: "Sleutel aanvragen: maak een gratis account op themoviedb.org en ga naar Instellingen → API. "
                      + "Zonder sleutel komen series van TVmaze en tonen films alleen hun titel. "
                      + "Dit product gebruikt de TMDB API, maar is niet door TMDB goedgekeurd of gecertificeerd."
            }

            Text {
                id: warning
                visible: text !== ""
                color: "#ff8a80"
                font.pixelSize: (setup.unit * 2.2) * appModel.fontScale
            }

            Row {
                spacing: setup.unit * 1.5
                FocusButton {
                    id: saveButton
                    unit: setup.unit
                    text: "Opslaan en zoeken"
                    onClicked: setup.save()
                    KeyNavigation.up: setup.showKey ? keyField : (setup.askPin ? pinField : moreButton)
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
                    KeyNavigation.up: setup.showKey ? keyField : (setup.askPin ? pinField : moreButton)
                    KeyNavigation.left: saveButton
                }
            }
        }
    }
}
