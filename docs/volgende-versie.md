# Plan volgende versie

Uit het logbestand van 16-11-2026 (Kijkluister 4.4.0):

## 2. Live tv: "403 Forbidden" bij zappen
Vijf zenders na elkaar weigerden (403), daarna werkte NPO 2 Extra wel. Waarschijnlijk: aanbieder staat 1 verbinding toe en de vorige stream was nog open,
of de aanbieder weigert de standaard User-Agent van FFmpeg (Lavf).
- Bij zappen eerst de oude stream echt stoppen (player.stop + source leeg) en ~0,5 s wachten.
- Bij 403: één keer opnieuw proberen na 2 s; anders melding "Je aanbieder weigert deze zender (misschien kijkt er al iemand anders)".
- User-Agent instelbaar maken (standaard zoals VLC) via de doorgifte (relay) als de aanbieder Lavf weigert.

## 4. Kleine dingen
- Zenderlogo's die niet laden (docdog.top…) worden in de gids steeds opnieuw geprobeerd: mislukte adressen onthouden en niet opnieuw laden.
- Time-out (-138) bij een zender: melding "Zender reageert niet" i.p.v. technische tekst.
- Logo's NLZIET en Simone FM ontbreken: eigen logo meeleveren.


## Beveiliging: nog open (bewust niet in 4.7.0)
- De ingebouwde TMDB- en Unsplash-sleutels zijn alleen verhuld (XOR), niet geheim: wie het programma uitpluist kan ze vinden. Alleen echt op te lossen met een eigen tussenserver.
- Kinderslot en kijktijd staan in settings.ini; een handig kind met een eigen Windows-beheerder kan die aanpassen. Afhankelijk van de Windows-rechten, niet van Kijkluister.
- Telefoonpagina gaat via http op het thuisnetwerk (geen https): iemand op hetzelfde wifi kan in theorie de code onderscheppen. Echte oplossing: de eigen Android-app met gekoppelde sleutel.
