// Knop "Hulp" (?) in de bovenbalk: welke knop doet wat, op controller, afstandsbediening en toetsenbord.
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick

FocusScope {
    id: help

    readonly property real unit: height / 100
    property Item returnFocusTo: null
    readonly property var rows: [
        { what: "Kiezen", pad: "Pijltjes / joystick", remote: "Pijltjes", key: "Pijltjes" },
        { what: "Openen", pad: "A", remote: "OK", key: "Enter" },
        { what: "Terug", pad: "B", remote: "Terug", key: "Esc" },
        { what: "Opties van een tegel (verplaatsen, kinderslot, ...)", pad: "A vasthouden of ☰", remote: "Menu / blauw", key: "Enter vasthouden of F2" },
        { what: "Naar het startscherm, vanuit elke app of website", pad: "Home / Xbox-knop", remote: "Home", key: "Esc 1 seconde vasthouden" },
        { what: "Website: vorige pagina", pad: "B", remote: "Terug", key: "Alt + ←" },
        { what: "Tegel 1 t/m 9 van de bovenste rij openen", pad: "—", remote: "Cijfers 1–9", key: "1–9" },
        { what: "Live tv: zender kiezen op nummer", pad: "—", remote: "Cijfers", key: "Cijfers" },
        { what: "Live tv: tv-gids / opnemen", pad: "Y / RB", remote: "Gids / rood", key: "I / R" },
        { what: "Live tv: gids van alle zenders", pad: "—", remote: "—", key: "G" },
        { what: "Live tv: vorige zender / zappen", pad: "—", remote: "0 / P+ P−", key: "0 / PgUp PgDn" },
        { what: "Tv-gids: herinnering / serie opnemen", pad: "—", remote: "—", key: "H / S" },
        { what: "Zoeken", pad: "Zoeken (bovenbalk)", remote: "Typen of 🎤", key: "Gewoon typen" },
        { what: "Radio: andere zender / volume", pad: "◀ ▶ / ▲ ▼", remote: "◀ ▶ / ▲ ▼", key: "◀ ▶ / ▲ ▼" },
        { what: "Slaaptimer", pad: "Y in de radio", remote: "Menu → Slaaptimer", key: "T in de radio" }
    ]

    anchors.fill: parent
    visible: false
    z: 120

    function open(focusItem) {
        returnFocusTo = focusItem
        visible = true
        forceActiveFocus()
        console.info("Help opened")
    }

    function close() {
        visible = false
        if (returnFocusTo) returnFocusTo.forceActiveFocus()
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back || event.key === Qt.Key_Backspace
                || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            close()
            event.accepted = true
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#f20b0c0f"
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: help.close() }
    }

    Column {
        x: help.unit * 6
        y: help.unit * 5
        width: parent.width - help.unit * 12
        spacing: help.unit * 1.2

        Text {
            text: "Hulp: welke knop doet wat?"
            color: "white"
            font.pixelSize: help.unit * 4.2 * appModel.fontScale
            font.weight: Font.DemiBold
        }

        // Kopregel
        Row {
            width: parent.width
            Repeater {
                model: ["", "🎮 Controller", "📺 Afstandsbediening", "⌨ Toetsenbord"]
                Text {
                    required property string modelData
                    required property int index
                    width: index === 0 ? parent.width * 0.4 : parent.width * 0.2
                    text: modelData
                    color: "#a8acb3"
                    font.pixelSize: help.unit * 2.2 * appModel.fontScale
                    font.weight: Font.DemiBold
                }
            }
        }

        Repeater {
            model: help.rows
            Rectangle {
                required property var modelData
                required property int index
                width: parent.width
                height: help.unit * 5.4
                radius: help.unit * 0.8
                color: index % 2 === 0 ? "#161a21" : "transparent"
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: help.unit
                    Repeater {
                        model: [modelData.what, modelData.pad, modelData.remote, modelData.key]
                        Text {
                            required property string modelData
                            required property int index
                            width: index === 0 ? parent.width * 0.4 : parent.width * 0.2
                            height: parent.height
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            text: modelData
                            color: index === 0 ? "white" : "#e6e8eb"
                            font.pixelSize: help.unit * 2.2 * appModel.fontScale
                        }
                    }
                }
            }
        }

        Text {
            topPadding: help.unit * 1.5
            text: "Druk op B, Esc of Enter om te sluiten."
            color: "#a8acb3"
            font.pixelSize: help.unit * 2.2 * appModel.fontScale
        }
    }
}
