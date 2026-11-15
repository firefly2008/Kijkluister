# Plan volgende versie

## Verder kijken (scherm, ResumeScreen.qml)
Gemeld 15-11-2026 met schermafbeelding:
- Tegel valt links buiten beeld: geen linkermarge, titel en jaartal beginnen tegen de schermrand.
- Selectiekader (wit) en grijze achtergrondkaart liggen verschoven over elkaar; kader loopt rechts over de kaart heen.
- Tegel is te groot voor één film; tekst (titel, "nog … min") te groot.
- Rest van het scherm leeg: tegels in een raster met dezelfde maten en marges als het startscherm, poster/achtergrond met donkere verloop onderaan, voortgangsbalk binnen de kaart.
- Met twee items (gemeld 15-11-2026, 2e schermafbeelding): de grijze kaart van de gekozen tegel schuift over de volgende tegel heen (geen tussenruimte); tweede tegel begint half onder de eerste.
- Bij series wordt de regel afgekapt ("S02E01 · Aflevering 1 · nog …"): resterende tijd op eigen regel of korter ("S2 A1 · nog 41 min").
- Niet-gekozen tegels zijn donker/vaag en hebben andere maten dan de gekozen tegel; alle tegels even groot, gekozen tegel alleen kader + gloed.
- Hints onderaan zijn goed.

## Films & Series: Esc werkt niet
Gemeld 15-11-2026: in Films & Series (LibraryScreen.qml) brengt Esc je niet terug naar het startscherm.
Esc moet overal één stap terug gaan (detail → lijst → startscherm), ook als de focus in het zoekveld, de filterrij of een submenu staat. Rooktest toevoegen: library + Esc → "Home screen".

## Schermtoetsenbord: geen Enter-toets
Gemeld 15-11-2026 (o.a. "Naam van het nieuwe profiel", SearchPicker.qml): het schermtoetsenbord heeft geen Enter/OK-knop.
Met afstandsbediening of controller kun je zo niet bevestigen zonder eerst naar rechts naar het resultaat te gaan.
Onderste rij: Spatie · ⌫ · Wissen · **OK** (accentkleur). OK doet hetzelfde als Enter op het eerste resultaat
(profiel opslaan, zoeken, zender toevoegen). Hint onderaan aanvullen. Rooktest: profiel aanmaken via OK.

## Instelling: starten met Windows
Gevraagd 15-11-2026: optie in Instellingen (Meer instellingen) "Kijkluister starten bij opstarten van Windows" (aan/uit).
- Aan: waarde in HKCU\Software\Microsoft\Windows\CurrentVersion\Run → "C:\Program Files\Kijkluister\kijkluister.exe" --autostart (per gebruiker, geen beheerdersrechten nodig).
- Uit: waarde verwijderen. Schakelaar toont de echte stand (register uitlezen).
- Na stille update blijft de waarde staan (pad verandert niet); bij verwijderen van Kijkluister de waarde opruimen (installer [UninstallDelete]/[Registry] uninsdeletevalue).
- Optioneel: bij --autostart direct schermvullend op het startscherm, geen welkomststap.
- Let op: de installer heeft al een (standaard uitgevinkte) taak "autostart" die een snelkoppeling in de map Opstarten zet ({userstartup}). Schakelaar moet die ook herkennen en bij Uit verwijderen, zodat er niet twee keer gestart wordt. Bij voorkeur één methode: de register-sleutel, en de installer-taak daarop laten aansluiten.
- Rooktest: aan → registerwaarde aanwezig, uit → weg.

## Suggesties (gekozen 15-11-2026: alle 12)
### Live tv
1. Gidsraster: alle zenders in één overzicht (nu + straks), tijdlijn horizontaal, zenders verticaal; Enter = kijken, R = opnemen.
2. Vorige zender: knop (0 of Terug kort in speler) wisselt tussen laatste twee zenders; PgUp/PgDn (P+/P−) zappen.
3. Herinnering: "Herinner me" bij programma in de gids; 2 min voor start melding met knop "Kijken" (ook als een andere dienst voorop staat: Kijkluister naar voren).
4. Serie opnemen: alle afleveringen van een titel op een zender automatisch opnemen (planning uit de gids, dubbele overslaan).
### Startscherm
5. Rij "Nu op tv": favoriete zenders met huidig programma en voortgang; Enter = direct kijken.
6. "Wie kijkt er?" bij opstarten als er >1 profiel is (uit te zetten).
7. Sfeerstand: na X min (instelbaar, standaard 10) niets doen → Schilderij; niet tijdens afspelen.
### Gemak
8. Geluid kiezen in de bovenbalk: lijst audio-uitgangen (tv/soundbar/koptelefoon), standaard-uitgang van Windows wisselen.
9. Telefoon als afstandsbediening: kleine webserver op het thuisnetwerk + QR-code in Instellingen; pijltjes, OK, Terug, Home, typen; koppelen met code.
10. Kijktijd kinderprofiel: maximum per dag; daarna pincode nodig; melding 5 min vooraf.
### Onderhoud
11. Back-up: zenders, profielen, tegels, instellingen naar één bestand (zonder wachtwoorden tenzij gekozen) + terugzetten.
12. Knop "Logbestand delen" in Instellingen: log + systeeminfo als zip op het bureaublad.
