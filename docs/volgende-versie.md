# Plan volgende versie

## Verder kijken (scherm, ResumeScreen.qml)
Gemeld 15-11-2026 met schermafbeelding:
- Tegel valt links buiten beeld: geen linkermarge, titel en jaartal beginnen tegen de schermrand.
- Selectiekader (wit) en grijze achtergrondkaart liggen verschoven over elkaar; kader loopt rechts over de kaart heen.
- Tegel is te groot voor één film; tekst (titel, "nog … min") te groot.
- Rest van het scherm leeg: tegels in een raster met dezelfde maten en marges als het startscherm, poster/achtergrond met donkere verloop onderaan, voortgangsbalk binnen de kaart.
- Hints onderaan zijn goed.

## Films & Series: Esc werkt niet
Gemeld 15-11-2026: in Films & Series (LibraryScreen.qml) brengt Esc je niet terug naar het startscherm.
Esc moet overal één stap terug gaan (detail → lijst → startscherm), ook als de focus in het zoekveld, de filterrij of een submenu staat. Rooktest toevoegen: library + Esc → "Home screen".

## Schermtoetsenbord: geen Enter-toets
Gemeld 15-11-2026 (o.a. "Naam van het nieuwe profiel", SearchPicker.qml): het schermtoetsenbord heeft geen Enter/OK-knop.
Met afstandsbediening of controller kun je zo niet bevestigen zonder eerst naar rechts naar het resultaat te gaan.
Onderste rij: Spatie · ⌫ · Wissen · **OK** (accentkleur). OK doet hetzelfde als Enter op het eerste resultaat
(profiel opslaan, zoeken, zender toevoegen). Hint onderaan aanvullen. Rooktest: profiel aanmaken via OK.
