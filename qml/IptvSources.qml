// Bronnen voor live tv beheren: M3U-link, M3U-bestand of Xtream Codes-account
// (de drie soorten die open-tv ook kent).
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Dialogs

FocusScope {
    id: sources

    readonly property real unit: height / 100
    property string addType: "m3u-url"
    property int confirmRemove: -1
    signal closed()

    anchors.fill: parent
    visible: false
    z: 100

    function open() {
        addType = "m3u-url"
        nameField.text = ""
        urlField.text = ""
        userField.text = ""
        passwordField.text = ""
        warning.text = ""
        confirmRemove = -1
        visible = true
        const first = sourceList.count > 0 ? sourceList : urlTab
        first.forceActiveFocus()
    }

    function close() {
        visible = false
        closed()
    }

    function add() {
        if (iptv.addSource(addType, nameField.text, urlField.text, userField.text, passwordField.text)) {
            close()
        } else {
            warning.text = addType === "xtream" ? "Vul server, gebruikersnaam en wachtwoord in."
                         : addType === "m3u-file" ? "Kies een bestaand M3U-bestand."
                         : "Vul het adres van de afspeellijst in."
        }
    }

    // Voorbeeld voor de handleiding
    function demoXtream() {
        addType = "xtream"
        nameField.text = "Mijn abonnement"
        urlField.text = "http://voorbeeld.tv:8080"
        userField.text = "gebruiker"
        passwordField.text = "geheim123"
        addButton.forceActiveFocus()
    }

    Keys.onEscapePressed: close()

    // Invoerveld dat met pijltjes bereikbaar is
    component Field: FocusScope {
        id: field
        property alias text: input.text
        property string placeholder
        property bool secret: false
        property real unit: 10
        property Item upItem: null
        property Item downItem: null
        height: unit * 6
        Rectangle {
            anchors.fill: parent
            radius: field.unit
            color: "#0f1115"
            border.width: input.activeFocus ? 3 : 1
            border.color: input.activeFocus ? "#e8eaed" : "#33ffffff"
        }
        TextInput {
            id: input
            anchors.fill: parent
            anchors.margins: field.unit * 1.5
            focus: true
            verticalAlignment: TextInput.AlignVCenter
            color: "white"
            font.pixelSize: field.unit * 2.3
            clip: true
            selectByMouse: true
            echoMode: field.secret ? TextInput.Password : TextInput.Normal
            KeyNavigation.up: field.upItem
            KeyNavigation.down: field.downItem
        }
        Text {
            anchors.fill: input
            verticalAlignment: Text.AlignVCenter
            visible: input.text === "" && !input.activeFocus
            color: "#7d8188"
            font.pixelSize: field.unit * 2.3
            text: field.placeholder
        }
    }

    FileDialog {
        id: fileDialog
        title: "M3U-afspeellijst kiezen"
        nameFilters: ["Afspeellijsten (*.m3u *.m3u8)", "Alle bestanden (*)"]
        onAccepted: urlField.text = iptv.localPath(selectedFile)
    }

    Rectangle {
        anchors.fill: parent
        color: "#d8000000"
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, sources.unit * 120)
        height: content.height + sources.unit * 8
        radius: sources.unit * 2
        color: "#1b1d22"
        border.color: "#33ffffff"
        border.width: 1

        Column {
            id: content
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: sources.unit * 4
            spacing: sources.unit * 1.4

            Text {
                color: "white"
                font.pixelSize: sources.unit * 4
                font.weight: Font.DemiBold
                text: "Bronnen voor live tv"
            }

            // --- Bestaande bronnen ---
            Text {
                visible: sourceList.count > 0
                color: "#9fb4d0"
                font.pixelSize: sources.unit * 2.2
                text: "Huidige bronnen (Enter om te verwijderen)"
            }
            ListView {
                id: sourceList
                width: parent.width
                height: Math.min(count, 3) * sources.unit * 7
                visible: count > 0
                clip: true
                spacing: sources.unit
                model: iptv.sources
                keyNavigationEnabled: true
                KeyNavigation.down: urlTab

                delegate: FocusButton {
                    required property int index
                    required property var modelData
                    unit: sources.unit
                    focus: ListView.isCurrentItem
                    text: sources.confirmRemove === index
                          ? "Nogmaals Enter om " + modelData.name + " te verwijderen"
                          : "✕   " + modelData.name + "   (" + (modelData.type === "xtream" ? "Xtream" : modelData.type === "m3u-file" ? "bestand" : "M3U-link") + ")"
                    onClicked: {
                        if (sources.confirmRemove === index) {
                            sources.confirmRemove = -1
                            iptv.removeSource(index)
                        } else {
                            sources.confirmRemove = index
                        }
                    }
                }
            }

            // --- Nieuwe bron ---
            Text {
                color: "#9fb4d0"
                font.pixelSize: sources.unit * 2.2
                text: "Bron toevoegen"
            }
            Row {
                spacing: sources.unit * 1.2
                FocusButton {
                    id: urlTab
                    unit: sources.unit
                    text: "M3U-link"
                    checked: sources.addType === "m3u-url"
                    onClicked: sources.addType = "m3u-url"
                    KeyNavigation.right: fileTab
                    KeyNavigation.up: sourceList.count > 0 ? sourceList : null
                    KeyNavigation.down: nameField
                }
                FocusButton {
                    id: fileTab
                    unit: sources.unit
                    text: "M3U-bestand"
                    checked: sources.addType === "m3u-file"
                    onClicked: sources.addType = "m3u-file"
                    KeyNavigation.left: urlTab
                    KeyNavigation.right: xtreamTab
                    KeyNavigation.up: sourceList.count > 0 ? sourceList : null
                    KeyNavigation.down: nameField
                }
                FocusButton {
                    id: xtreamTab
                    unit: sources.unit
                    text: "Xtream Codes"
                    checked: sources.addType === "xtream"
                    onClicked: sources.addType = "xtream"
                    KeyNavigation.left: fileTab
                    KeyNavigation.up: sourceList.count > 0 ? sourceList : null
                    KeyNavigation.down: nameField
                }
            }

            Field {
                id: nameField
                width: parent.width
                unit: sources.unit
                placeholder: "Naam (mag leeg blijven)"
                upItem: urlTab
                downItem: urlField
            }
            Row {
                spacing: sources.unit * 1.2
                Field {
                    id: urlField
                    width: content.width - (fileButton.visible ? fileButton.width + parent.spacing : 0)
                    unit: sources.unit
                    placeholder: sources.addType === "xtream" ? "Server, bijvoorbeeld http://voorbeeld.tv:8080"
                               : sources.addType === "m3u-file" ? "Pad naar het .m3u-bestand"
                               : "Adres van de afspeellijst (http://… .m3u)"
                    upItem: nameField
                    downItem: fileButton.visible ? fileButton : sources.addType === "xtream" ? userField : addButton
                }
                FocusButton {
                    id: fileButton
                    visible: sources.addType === "m3u-file"
                    unit: sources.unit
                    text: "Bestand kiezen…"
                    onClicked: fileDialog.open()
                    KeyNavigation.up: nameField
                    KeyNavigation.left: urlField
                    KeyNavigation.down: addButton
                }
            }
            Field {
                id: userField
                visible: sources.addType === "xtream"
                width: parent.width
                unit: sources.unit
                placeholder: "Gebruikersnaam"
                upItem: urlField
                downItem: passwordField
            }
            Field {
                id: passwordField
                visible: sources.addType === "xtream"
                width: parent.width
                unit: sources.unit
                secret: true
                placeholder: "Wachtwoord"
                upItem: userField
                downItem: addButton
            }

            Text {
                width: parent.width
                wrapMode: Text.Wrap
                color: "#9a9ea6"
                font.pixelSize: sources.unit * 1.9
                text: "Gebruik alleen afspeellijsten waarvoor je een abonnement of toestemming hebt. "
                      + "Gegevens worden alleen op deze pc bewaard."
            }
            Text {
                id: warning
                visible: text !== ""
                color: "#ff8a80"
                font.pixelSize: sources.unit * 2.2
            }

            Row {
                spacing: sources.unit * 1.5
                FocusButton {
                    id: addButton
                    unit: sources.unit
                    text: "Toevoegen en laden"
                    onClicked: sources.add()
                    KeyNavigation.right: freeButton
                    KeyNavigation.up: sources.addType === "xtream" ? passwordField : sources.addType === "m3u-file" ? fileButton : urlField
                }
                FocusButton {
                    id: freeButton
                    unit: sources.unit
                    text: "Gratis zenders"
                    onClicked: {
                        const n = iptv.addFreeSources()
                        warning.text = n > 0 ? n + " gratis lijst(en) toegevoegd." : "De gratis lijsten staan er al."
                    }
                    KeyNavigation.left: addButton
                    KeyNavigation.right: closeButton
                    KeyNavigation.up: addButton.KeyNavigation.up
                }
                FocusButton {
                    id: closeButton
                    unit: sources.unit
                    text: "Sluiten"
                    onClicked: sources.close()
                    KeyNavigation.left: freeButton
                    KeyNavigation.up: addButton.KeyNavigation.up
                }
            }
        }
    }
}
