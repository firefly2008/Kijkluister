# Plan volgende versie

## Verder kijken: resterende tijd op eigen regel
In 4.4.0 splitst ResumeScreen op " · nog ", maar de tekst uit resumemodel is "S02E04 · Down  ·  nog 3 min" (dubbele spaties),
dus de tijd blijft op dezelfde regel. Splitsen met een reguliere expressie (/\s+·\s+nog /).

## Engels: losse resten
- "Geluid via… (standaard)": `|| "standaard"` in Main.qml niet vertaald. Zoek meer `|| "…"`-teksten en wrap met qsTr.
