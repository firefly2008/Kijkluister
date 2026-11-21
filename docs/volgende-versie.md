# Plan volgende versie

Geen open bouwpunten. Zappen/403 en de kleine dingen zijn gebouwd in 4.9.0.

## Beveiliging: nog open (bewust niet in 4.7.0)
- De ingebouwde TMDB- en Unsplash-sleutels zijn alleen verhuld (XOR), niet geheim: wie het programma uitpluist kan ze vinden. Alleen echt op te lossen met een eigen tussenserver.
- Kinderslot en kijktijd staan in settings.ini; een handig kind met een eigen Windows-beheerder kan die aanpassen. Afhankelijk van de Windows-rechten, niet van Kijkluister.
- Telefoonpagina gaat via http op het thuisnetwerk (geen https): iemand op hetzelfde wifi kan in theorie de code onderscheppen. Echte oplossing: de eigen Android-app met gekoppelde sleutel.
