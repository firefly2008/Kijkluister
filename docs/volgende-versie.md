# Plan volgende versie

Uit het logbestand van 16-11-2026 (Kijkluister 4.4.0):

## 1. Inloggegevens in het logbestand (privacy)
Zenderadressen van een Xtream-paneel bevatten gebruikersnaam en wachtwoord in het pad (`http://server:8080/<gebruiker>/<wachtwoord>/<id>`).
Ze komen zo in `IPTV play error` en in "Logbestand delen". Het filter in shareLog vangt alleen `password=` in de query.
- Bij het loggen van zenderadressen: alleen server + stream-id (`http://server:8080/…/1332`).
- shareLog: ook het padpatroon `/<x>/<y>/<cijfers>` na host:poort maskeren.

## 2. Live tv: "403 Forbidden" bij zappen
Vijf zenders na elkaar weigerden (403), daarna werkte NPO 2 Extra wel. Waarschijnlijk: aanbieder staat 1 verbinding toe en de vorige stream was nog open,
of de aanbieder weigert de standaard User-Agent van FFmpeg (Lavf).
- Bij zappen eerst de oude stream echt stoppen (player.stop + source leeg) en ~0,5 s wachten.
- Bij 403: één keer opnieuw proberen na 2 s; anders melding "Je aanbieder weigert deze zender (misschien kijkt er al iemand anders)".
- User-Agent instelbaar maken (standaard zoals VLC) via de doorgifte (relay) als de aanbieder Lavf weigert.

## 3. Foutmeldingen bij afsluiten
Bij het afsluiten (07:20:33) ~100 meldingen "Cannot read property … of null" (remote, usage, profiles, updater, radio…):
de C++-objecten worden vóór het QML-venster opgeruimd. Venster/engine eerst afbreken (bij aboutToQuit) zodat er geen bindingen meer lopen.

## 4. Kleine dingen
- Zenderlogo's die niet laden (docdog.top…) worden in de gids steeds opnieuw geprobeerd: mislukte adressen onthouden en niet opnieuw laden.
- Time-out (-138) bij een zender: melding "Zender reageert niet" i.p.v. technische tekst.
- Logo's NLZIET en Simone FM ontbreken: eigen logo meeleveren.

## 5. Logo ontbreekt op de telefoon-afstandsbediening
Oorzaak: in remoteserver.cpp `respond(socket, f.open(...) ? 200 : 404, "image/png", f.readAll())` — de volgorde waarin C++ argumenten uitrekent
ligt niet vast; MSVC doet `f.readAll()` vóór `f.open()`, dus een leeg plaatje met status 200 (daarom slaagde de test wel).
Eerst openen en lezen, dan antwoorden. Rooktest: grootte van /icon-192.png > 1000 bytes (en /icon-512.png, /icon-maskable.png).
Daarna op de telefoon: de snelkoppeling op het beginscherm opnieuw toevoegen (Chrome bewaart het oude, lege pictogram).
