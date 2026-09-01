# Umbenennung SkyScope → Chocks — Reviewplan

Stand: 2026-09-01. **Noch nichts ausgeführt** (außer Backup-Tarball, siehe §0).

---

## 0. Backup-Status

**Erledigt:** Vollständiges Tarball-Snapshot des Ordners inkl. `.git`, gestagter *und*
ungestagter Änderungen und untracked Files:

`SkyScope-backup-<timestamp>.tar.gz` (637 KB, 524 Einträge)

**Nicht erledigt: Git-Tag/Branch.** Ich kann in diesem Repo keine Git-Schreiboperation
abschließen — die Sandbox darf Dateien anlegen, aber nicht löschen, und Git braucht zum
Aufräumen seiner Lock-Files ein `unlink`. Dabei sind Reste liegengeblieben, die **vor dem
ersten Git-Kommando** weg müssen (Schritt 1 unten). Sorry — mein Fehler beim Sondieren.

---

## 1. Aufräumen + Backup (zuerst ausführen, Terminal)

```bash
cd ~/Projects/SkyScope

# Von mir hinterlassene Lock-/Testdateien entfernen
rm -f .git/index.lock .git/packed-refs.lock
rm -f .git/refs/tags/backup/test-probe.lock
rm -rf .git/refs/tags/backup
rm -f _wt_test .git/_writetest
git tag -d backup/test-probe 2>/dev/null || true

# Kontrolle: muss sauber durchlaufen
git status

# Backup: kompletter Ist-Zustand als Commit + Tag + Branch
git add -A
git commit -m "WIP: Stand vor Chocks-Umbenennung (Backup)"
git tag backup/pre-chocks-rename
git branch backup/pre-chocks-rename
```

Wiederherstellung jederzeit mit `git reset --hard backup/pre-chocks-rename`.
Der WIP-Commit lässt sich später mit `git reset --soft HEAD~1` wieder auflösen.

---

## 2. Namenskonvention (Entscheidung: durchgehend „Chocks")

| Kategorie | Wert |
|---|---|
| Xcode-Projekt | `Chocks.xcodeproj` |
| App-Target / Modulname | `Chocks` |
| Widget-Target | `Chocks WidgetExtension` |
| Produkte | `Chocks.app`, `Chocks WidgetExtension.appex` |
| Anzeigename (CFBundleDisplayName/Name) | `Chocks` |
| Ordner | `Chocks Widget/`, zuletzt `~/Projects/Chocks` |

**Bleibt bewusst klein** (technisch bzw. semantisch erforderlich):

- URL-Scheme `chocks://` — Schemes gehören per RFC 3986 kleingeschrieben; Änderung würde
  außerdem alle Widget-Deeplinks brechen (`NavigationCoordinator.swift:33`,
  `ChocksWidgetLiveActivity.swift:16`).
- App Group `group.com.puffblende.chocks`
- Reverse-DNS-Identifier: `com.chocks.app`, `com.chocks.bgrefresh`,
  `com.chocks.openSky` (Keychain-Service), `com.chocks.widget.control`
- `AppSettings.swift:331` `legacyKeychainService = "DK.SkyScope"` — **nicht anfassen**,
  migriert bestehende Keychain-Einträge. Ich ergänze dort einen erklärenden Kommentar.

---

## 3. Zwei Bundle-ID-Varianten

Das Skript nimmt `A` oder `B` als Argument.

**Variante A** — Bundle-ID wechselt (nur möglich, wenn *kein* App-Store-Connect-Record für
`DK.SkyScope` existiert bzw. noch nichts eingereicht wurde):

- App: `com.puffblende.chocks`
- Widget: `com.puffblende.chocks.widget`
- Folgearbeiten: neue App-ID + App Group im Developer-Portal, neue Provisioning-Profiles
  (macht Xcode bei Automatic Signing selbst), **neue Firebase-iOS-App + neue
  `GoogleService-Info.plist`** (übernimmst du per Browser), APNs-Capability auf der neuen App-ID.
- Vorteil: konsistent mit App Group und Zielnamen.

**Variante B** — Bundle-ID bleibt `DK.SkyScope` / `DK.SkyScope.SkyScope-Widget`:

- Nur Namen, Pfade, Targets, Anzeigename ändern.
- Firebase unverändert, keine neuen Profiles, App-Store-Connect-Record bleibt gültig.
- Nachteil: interne ID passt nicht zum Namen (für Nutzer unsichtbar).

> Diese Entscheidung ist noch offen — sie hängt an deiner ASC-Prüfung. Bis dahin bitte
> nicht ausführen.

---

## 4. Fundstellen → Aktion (Datei für Datei)

### 4.1 Umbenennungen

| Von | Nach | Hinweis |
|---|---|---|
| `SkyScope.xcodeproj/` | `Chocks.xcodeproj/` | |
| `…/xcschemes/SkyScope.xcscheme` | `Chocks.xcscheme` | |
| `…/xcschemes/SkyScope WidgetExtension.xcscheme` | `Chocks WidgetExtension.xcscheme` | |
| `chocks Widget/` | `Chocks Widget/` | **case-only** → 2-Schritt-Rename |
| `chocks-Info.plist` | `Chocks-Info.plist` | **case-only** |
| `chocks.entitlements` | `Chocks.entitlements` | **case-only** |
| `chocks WidgetExtension.entitlements` | `Chocks WidgetExtension.entitlements` | **case-only** |
| `Chocks Widget/SkyScope_Widget.swift` | `ChocksWidget.swift` | Struct heißt schon `ChocksWidget` |
| `Chocks Widget/SkyScope_WidgetBundle.swift` | `ChocksWidgetBundle.swift` | |
| `Chocks Widget/SkyScope_WidgetLiveActivity.swift` | `ChocksWidgetLiveActivity.swift` | |
| `Chocks Widget/SkyScope_WidgetControl.swift` | `ChocksWidgetControl.swift` | |

APFS ist case-insensitive → reine Groß-/Kleinschreibungs-Renames brauchen einen
Zwischenschritt, sonst schluckt Git sie stillschweigend.

### 4.2 Löschungen (Karteileichen, nicht in der Build-Phase)

- `LiveActivityManager 2.swift` — alte Kopie, 8× `SkyScopeActivityAttributes`
- `Services/LiveActivityManager.swift` — alte Kopie, 7× `SkyScopeActivityAttributes`
- `Services/AirportCoordinatesService.swift` **bleibt** — geprüft: gebaut wird die
  Root-Variante `AirportCoordinatesService.swift`; die Services-Datei ist nicht in der
  Sources-Phase. *Vor dem Löschen prüfen, ob sie inhaltlich identisch ist* (steht im Skript).

Kompiliert wird `./LiveActivityManager.swift` (Root) — die ist bereits Chocks-sauber.

### 4.3 `Chocks.xcodeproj/project.pbxproj` (48 Treffer)

Ein globales `s/SkyScope/Chocks/g` erledigt alles auf einmal und **repariert nebenbei die
aktuell kaputten Pfade** (`SkyScope.entitlements`, `SkyScope-Info.plist`,
`SkyScope Widget/Info.plist` zeigen ins Leere, weil die Dateien auf der Platte schon
`chocks*` heißen — nach Schritt 4.1 heißen sie `Chocks*` und passen exakt):

- Target-Namen `SkyScope`, `SkyScope WidgetExtension` (`name` + `productName`)
- `SkyScope.app`, `SkyScope WidgetExtension.appex`
- `INFOPLIST_FILE`, `CODE_SIGN_ENTITLEMENTS` (4 Stellen, aktuell defekt)
- `INFOPLIST_KEY_CFBundleDisplayName = "SkyScope Widget"`
- `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "SkyScope uses your location…"`
- Kommentare der Build-Configuration-Listen (kosmetisch)

Danach werden die beiden `PRODUCT_BUNDLE_IDENTIFIER`-Zeilen **explizit** auf den Wert der
gewählten Variante gesetzt — deshalb ist Variante B trotz des globalen `sed` sauber.

Die `PBXFileSystemSynchronizedRootGroup` des Widget-Targets zeigt auf `chocks Widget` und
wird vom globalen sed nicht erfasst (Kleinschreibung) → separater sed im Skript.

### 4.4 Scheme-Dateien

Globales `s/SkyScope/Chocks/g` (`BuildableName`, `BlueprintName`, `ReferencedContainer`).

`Chocks.xcodeproj/xcuserdata/dennis.xcuserdatad/xcschemes/xcschememanagement.plist`
(2 Treffer) ist gitignored → wird gelöscht, Xcode legt sie neu an.

### 4.5 `Chocks-Info.plist`

Per `PlistBuddy` (nicht sed — `<string>chocks</string>` steht auch beim URL-Scheme, das
klein bleiben muss):

- `CFBundleDisplayName` → `Chocks`
- `CFBundleName` → `Chocks`
- `NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`,
  `NSLocationAlwaysAndWhenInUseUsageDescription` → Satzanfang `Chocks …`

Unverändert: `CFBundleURLSchemes: chocks`, `CFBundleURLName: com.chocks.app`,
`BGTaskSchedulerPermittedIdentifiers: com.chocks.bgrefresh`.

### 4.6 Swift-Quellcode

- `Views/HelpView.swift`, `Views/OnboardingView.swift`, `Views/FeedbackView.swift`:
  nutzerlesbarer Fließtext, ~20 Stellen `chocks` → `Chocks`. Diese drei Dateien enthalten
  **keine** Identifier, deshalb ist ein Wort-genaues sed hier sicher.
- `LiveActivityManager.swift:56` und `ChocksWidgetLiveActivity.swift` (3 Previews):
  `userLocation: "chocks"` → `"Chocks"` (Anzeigetext).
- Header-Kommentare `//  chocks Widget` in den 4 Widget-Dateien → `//  Chocks Widget`.
- `Models/AppSettings.swift:331`: unverändert, nur Kommentar ergänzen.

### 4.7 Sonstiges

- `.claude/settings.local.json`: alle `/Users/dennis/Projects/SkyScope`-Pfade,
  `SkyScopeApp.swift`, `-scheme SkyScope` → neue Werte.
- `CLAUDE.md`: Architektur-Baum nennt `chocksActivityAttributes.swift` → `ChocksActivityAttributes.swift`.
- `GoogleService-Info.plist`: **nicht anfassen** — kommt bei Variante A komplett neu aus
  der Firebase-Console (dein Part).
- `.gitignore`, SPM (`firebase-ios-sdk`): nicht betroffen. Keine Pods/Fastlane/CI/Tests vorhanden.

---

## 5. Verifikation (im Skript enthalten)

```bash
# 1. Es dürfen nur noch zwei erlaubte Treffer übrig sein
grep -ri skyscope . --exclude-dir=.git --exclude-dir=xcuserdata
#   erwartet: AppSettings.swift (legacyKeychainService)
#             GoogleService-Info.plist (bei Variante B auch project.pbxproj-Bundle-IDs)

# 2. Projekt lädt und baut
xcodebuild -project Chocks.xcodeproj -scheme Chocks \
           -destination 'generic/platform=iOS' -configuration Debug build

# 3. Widget-Target
xcodebuild -project Chocks.xcodeproj -scheme 'Chocks WidgetExtension' \
           -destination 'generic/platform=iOS' -configuration Debug build
```

Zusätzlich manuell in Xcode: Signing & Capabilities beider Targets prüfen (App Group,
Push, Live Activities), einmal auf dem Simulator starten, Live Activity und Widget-Deeplink
(`chocks://aircraft/…`) testen.

---

## 6. Allerletzter Schritt — Projektordner

Erst **nachdem** der Build grün ist und du zufrieden bist:

```bash
cd ~/Projects && mv SkyScope Chocks
```

Danach: Xcode-Recent-Projects aufräumen, `.claude/settings.local.json` erneut prüfen, und
mir den Ordner neu freigeben (mein Zugriff bricht beim Umbenennen ab).

---

## 7. Was danach noch Xcode-UI / Web braucht

| Aufgabe | Wo | Variante |
|---|---|---|
| App-ID `com.puffblende.chocks` anlegen | developer.apple.com | A |
| App Group der neuen App-ID zuordnen | developer.apple.com | A |
| Push-Capability auf neuer App-ID | developer.apple.com | A |
| Provisioning-Profiles | Xcode, automatisch beim Build | A |
| Firebase-App + neue `GoogleService-Info.plist` | Console (dein Part) | A |
| App-Name / Record | App Store Connect | A + B |
| Signing-Team-Zuordnung prüfen (`9XW69X88LP`) | Xcode | A + B |

Alles andere läuft über das Skript.
