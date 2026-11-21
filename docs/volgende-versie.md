# Plan volgende versie (voorgesteld 4.10.0)

Gevraagd op 21-11-2026, nog niet gebouwd ("niet nu").

## 1. Eigen TMDB- en Unsplash-sleutels (ingebouwde sleutels eruit)
- Ingebouwde sleutels (XOR-verhuld) verdwijnen uit het programma en uit de build (geen TMDB_TOKEN/UNSPLASH_TOKEN-secrets meer nodig).
- Gebruiker vult zelf zijn sleutel in: Instellingen → Sleutels (invoer via schermtoetsenbord of telefoonpagina). Opslag versleuteld via securestore (DPAPI), nooit in logbestand.
- Op dat scherm per dienst een uitleg en het adres waar de sleutel wordt aangemaakt:
  - TMDB: https://www.themoviedb.org/settings/api (gratis account, "API Read Access Token")
  - Unsplash: https://unsplash.com/oauth/applications (nieuwe app, "Access Key")
  Adres als tekst en als QR-code, zodat het met de telefoon is te openen.
- Zonder sleutel: functie rustig uitgeschakeld met een melding die naar dit scherm verwijst (geen foutmelding). Eerste-start-hulp (Welkom) noemt het kort.
- Bestaande installaties: sleutel ontbreekt na de update; eenmalige melding. Releasenotes vermelden dit duidelijk.
- Controleknop "Testen": één verzoek naar de dienst, toont "Sleutel werkt" of "Sleutel geweigerd".

## 2. Kinderslot en kijktijd beter beschermen (voorstel, nog te bevestigen)
- Pincode, kinderslot en kijktijdlimieten uit settings.ini halen en opslaan in securestore (DPAPI, gebonden aan het Windows-account van de ouder), met een handtekening zodat aanpassen van het bestand wordt opgemerkt (dan: slot blijft aan / standaard streng).
- Pincode alleen als hash met salt, nooit leesbaar.
- Eerlijke beperking in de uitleg: een kind met een eigen Windows-beheerdersaccount kan dit nooit helemaal tegenhouden. Advies in de app: kinderen een gewoon account geven.
- Vraag aan gebruiker vóór bouwen: bedoel je alleen dit, of ook een aparte "ouderkluis" met aparte pincode voor instellingen?

## Beveiliging: nog open
- (Wordt in de volgende versie aangepakt, zie punt 1.) De ingebouwde TMDB- en Unsplash-sleutels zijn alleen verhuld.
- (Zie punt 2.) Kinderslot en kijktijd staan in settings.ini.
- Telefoonpagina gaat via http op het thuisnetwerk (geen https): iemand op hetzelfde wifi kan in theorie de code onderscheppen. Echte oplossing: de eigen Android-app met gekoppelde sleutel.
