chocks – Projektbriefing für Claude
Was ist chocks?
chocks ist eine iOS-App für Aviation-Enthusiasten (insbesondere Privatpiloten), die Echtzeit-Flugzeugdaten aus der näheren Umgebung des Users abruft und anzeigt. Die App existiert bereits als Desktop-Applikation (Python, Windows/macOS, ca. 90% fertig). Die iOS-App ist eine eigenständige, abgespeckte Mobile-Version – keine Synchronisation mit der Desktop-App nötig, da beide dieselben externen APIs nutzen.


Technischer Kontext
Plattform
iOS (SwiftUI, Swift)
Xcode 26.5
Minimum iOS Version: iOS 16 (wegen Live Activities)
Datenquellen – Flugzeugdaten
Primär: FlightAware API
Fallback: OpenSky Network API (bei Überschreitung des täglichen Free-Limits von FlightAware)
Keine eigene Backend-Infrastruktur – die App spricht direkt mit den APIs
Keine Synchronisation zwischen Desktop- und iOS-App nötig
Datenquellen – Aeronautische Kartendaten
Für die Darstellung von Lufträumen, Flughäfen, NAVAIDs und Airways auf der Karte:

OpenAIP (https://www.openaip.net)

Weltweite aeronautische Daten: Lufträume, Flughäfen, NAVAIDs, Airways
Kostenlos, API verfügbar
Lizenz: CC BY-NC 4.0 – darf in kommerziellen Apps verwendet werden solange die Daten nicht exklusiv verkauft werden
Primäre Quelle für Europa/weltweit

Open Flightmaps (https://www.openflightmaps.org)

Hochqualitative VFR-Kartendaten speziell für DACH (Deutschland, Österreich, Schweiz)
Open Source, kostenlos
Ergänzende Quelle für detaillierte VFR-Daten im deutschsprachigen Raum

Geplante Kartenebenen (togglebar in Settings):

Lufträume (Class A-G, Special Use Airspace)
Flughäfen & Landeplätze
NAVAIDs (VORs, NDBs)
Airways
Standort
Die App nutzt den GPS-Standort des iPhones
Background Mode: Location Updates (damit die App auch bei gesperrtem Screen aktiv bleibt)


Features (v1.0)
1. Hauptansicht – Karte
Karte als primäre Ansicht (MapKit)
Eigener Standort in der Mitte
Einstellbarer Suchradius als Kreis eingeblendet (Standard: z.B. 50 km / 27 NM)
Flugzeug-Icons auf der Karte, orientiert nach Flugrichtung
Tap auf Flugzeug → Detail-Sheet von unten (Bottom Sheet):
Flugnummer, Airline
Flugzeugtyp
Höhe (ft/m einstellbar)
Geschwindigkeit (kts/km/h einstellbar)
Richtung
Von → Nach (Start/Zielflughafen)
2. Tab-Bar Navigation
🗺️ Map – Hauptansicht
📋 Liste – alle Flugzeuge im Radius, sortiert nach Distanz
⭐ Favoriten – gespeicherte Flugzeugkennzeichen (z.B. Vereinsflugzeuge)
⚙️ Settings
3. Settings
Allgemein:

Suchradius (in km oder NM – Piloten denken in Nautical Miles!)
Einheiten: metrisch / imperial (Höhe in ft oder m, Geschwindigkeit in kts oder km/h)
Refresh-Intervall: 1 / 2 / 5 / 10 Minuten (wegen Datensparsamkeit einstellbar)

Live Activity:

"Launch Live Activity on App Startup" (Checkbox, Standard: ein)

Siri:

Siri-Shortcut einrichten

Daten:

Primäre API: FlightAware (Standard)
Fallback API: OpenSky Network (Checkbox, Standard: ein)

Kartenebenen (togglebar):

Lufträume anzeigen (OpenAIP)
Flughäfen & Landeplätze anzeigen (OpenAIP / Open Flightmaps)
NAVAIDs anzeigen (OpenAIP)
Airways anzeigen (OpenAIP)
4. Live Activity (Dynamic Island + Lock Screen)
chocks Modus (Standard):

Startet automatisch beim App-Start (wenn Setting aktiv)
Rotiert durch alle Flugzeuge im Radius
Zeigt vom User definierte Felder (Flugnummer, Höhe, Geschwindigkeit, etc.)
Update-Intervall: identisch mit App-Refresh-Intervall
Läuft weiter wenn App im Hintergrund ist (via Location Background Mode)

Favorit Modus:

Wird aktiv wenn ein gespeicherter Favorit (Kennzeichen) erkannt wird
Notification: "D-EVGK ist in der Luft – Favorit verfolgen?"
Bei "Ja": chocks Live Activity stoppt, Favorit Live Activity startet
Zeigt nur dieses eine Flugzeug mit allen Details
Endet automatisch wenn Favorit landet → kurze "Gelandet"-Meldung
Optional: Rückkehr zu chocks Modus nach Landung
5. Favoriten-Widget (Home Screen & Lock Screen)
Da klassische Widgets keine Echtzeit-Daten unterstützen, zeigt das Widget ausschließlich Favoriten-Status:

┌─────────────────────────┐

│ ✈️ chocks               │

│ Aktuell kein Favorit    │

│ in der Luft             │

└─────────────────────────┘

┌─────────────────────────┐

│ ✈️ chocks               │

│ D-EVGK in der Luft! ✈️  │

│ Gestartet in EDSB       │

│ vor 11 Min              │

└─────────────────────────┘

Widget pollt Favoriten-Status (nicht alle Flugzeuge) – datensparend
Tap auf Widget → öffnet App direkt auf Favoriten-Tab
6. Siri Integration (App Intents)
Trigger: "Hey Siri, was fliegt gerade über mir?"
Radius wird für diese Abfrage auf 10 km reduziert
Siri liest Ergebnis vor, z.B.: "Gerade befinden sich 3 Flugzeuge in deiner Nähe. Am nächsten ist ein Airbus A320 der Lufthansa, Flug LH441 von München nach Hamburg, auf 8.200 Fuß."
Funktioniert auch wenn App im Hintergrund ist


App Architektur
Empfohlenes Pattern: MVVM
chocks/

├── Models/

│   ├── Aircraft.swift          # Flugzeug-Datenmodell

│   ├── Favorite.swift          # Favoriten-Modell

│   └── AppSettings.swift       # User-Einstellungen

├── ViewModels/

│   ├── MapViewModel.swift      # Karten-Logik

│   ├── ListViewModel.swift     # Listen-Logik

│   └── FavoritesViewModel.swift

├── Views/

│   ├── MapView.swift

│   ├── ListView.swift

│   ├── FavoritesView.swift

│   ├── SettingsView.swift

│   └── Components/

│       ├── AircraftDetailSheet.swift

│       └── AircraftAnnotation.swift

├── Services/

│   ├── LocationService.swift   # GPS & Background Location

│   ├── FlightAwareService.swift

│   ├── OpenSkyService.swift

│   ├── APIRouter.swift         # Fallback-Logik FA → OpenSky

│   ├── OpenAIPService.swift    # Lufträume, Flughäfen, NAVAIDs, Airways

│   └── OpenFlightmapsService.swift  # VFR-Daten DACH

├── LiveActivity/

│   ├── ChocksActivityAttributes.swift

│   └── FavoriteActivityAttributes.swift

├── Widget/

│   └── FavoriteWidget.swift

├── Intents/

│   └── WhatsOverMeIntent.swift # Siri App Intent

└── CLAUDE.md                   # Diese Datei
Datenpersistenz
UserDefaults: Settings (Radius, Einheiten, Refresh-Intervall)
SwiftData oder UserDefaults: Favoriten-Liste (Kennzeichen)
Keine Remote-Datenbank nötig


Wichtige Entscheidungen & Begründungen
Entscheidung
Begründung
Karte als Hauptansicht
Aviation-Enthusiasten erwarten räumliche Darstellung
Live Activity statt Widget für Echtzeit
iOS Widgets zu träge für Flugzeugdaten
Widget nur für Favoriten
Sinnvoller Use-Case, Widget-Refresh reicht aus
Kein eigener Server
Unnötige Komplexität, beide APIs direkt ansprechbar
Einstellbarer Refresh
Datensparsamkeit, User hat Kontrolle
Radius in NM
Piloten denken in Nautical Miles
Einmaliger Kaufpreis ~€1,99
Keine Abo-Verpflichtung, niedrige Hemmschwelle



Zielgruppe
Privatpiloten
Aviation-Enthusiasten / Plane Spotter
Vereinsmitglieder die Vereinsflugzeuge tracken wollen
Monetarisierung
Einmaliger Kaufpreis: ca. €1,99
Kein Abo, keine In-App-Purchases (v1.0)
Apple Developer Program: $99/Jahr


Was noch offen ist
Genaues Design / UI der Live Activity
Welche Felder der User für die Live Activity konfigurieren kann
App-Icon & Name final bestätigt (aktuell: "chocks")
App Store Screenshots & Beschreibung (später)

