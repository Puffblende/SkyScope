#!/bin/bash
#
# SkyScope -> Chocks, Variante A (Bundle-ID wechselt auf com.puffblende.chocks)
#
# Ausfuehren auf dem Mac:
#   chmod +x rename-to-chocks.sh
#   ./rename-to-chocks.sh
#
# Das Skript bricht bei jedem Fehler ab (set -e) und legt vorher einen
# Backup-Tag + -Branch an. Der uebergeordnete Ordner ~/Projects/SkyScope wird
# BEWUSST NICHT umbenannt - das ist der separate letzte Schritt.

set -euo pipefail

PROJ="$HOME/Projects/SkyScope"
APP_ID="com.puffblende.chocks"
WIDGET_ID="com.puffblende.chocks.widget"

cd "$PROJ"

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
say "0/9  Reste der Analyse-Session entfernen"
# ---------------------------------------------------------------------------
rm -f .git/index.lock .git/packed-refs.lock
rm -f .git/refs/tags/backup/test-probe.lock
rm -rf .git/refs/tags/backup
rm -f _wt_test _wt_test2 .git/_writetest
git tag -d backup/test-probe 2>/dev/null || true
git status >/dev/null   # muss ohne Lock-Warnung durchlaufen

# ---------------------------------------------------------------------------
say "1/9  Backup (Commit + Tag + Branch, inkl. ungestagter Aenderungen)"
# ---------------------------------------------------------------------------
git add -A
git commit -m "WIP: Stand vor Chocks-Umbenennung (Backup)" || echo "  (nichts zu committen)"
git tag -f backup/pre-chocks-rename
git branch -f backup/pre-chocks-rename
echo "  Wiederherstellung: git reset --hard backup/pre-chocks-rename"

# ---------------------------------------------------------------------------
say "2/9  Karteileichen loeschen"
# ---------------------------------------------------------------------------
for f in "LiveActivityManager 2.swift" "Services/LiveActivityManager.swift"; do
  if [ -f "$f" ]; then git rm -f --quiet "$f" 2>/dev/null || rm -f "$f"; echo "  geloescht: $f"; fi
done

# Services/AirportCoordinatesService.swift ist ebenfalls nicht in der Build-Phase.
# Nicht automatisch loeschen - erst pruefen:
if [ -f "Services/AirportCoordinatesService.swift" ]; then
  if diff -q "AirportCoordinatesService.swift" "Services/AirportCoordinatesService.swift" >/dev/null 2>&1; then
    echo "  HINWEIS: Services/AirportCoordinatesService.swift ist identisch mit der Root-Datei"
    echo "           (nicht im Build). Manuell loeschen, wenn gewuenscht."
  else
    echo "  HINWEIS: Services/AirportCoordinatesService.swift weicht von der Root-Datei ab."
    echo "           NICHT angefasst - bitte selbst pruefen."
  fi
fi

# ---------------------------------------------------------------------------
say "3/9  Dateien und Ordner umbenennen"
# ---------------------------------------------------------------------------
# APFS ist case-insensitive: reine Gross-/Kleinschreibungs-Renames brauchen
# einen Zwischenschritt, sonst schluckt Git sie stillschweigend.
casemv() {   # $1 = alt, $2 = neu
  [ -e "$1" ] || { echo "  uebersprungen (fehlt): $1"; return 0; }
  git mv "$1" "$1.__tmp__" && git mv "$1.__tmp__" "$2"
  echo "  $1 -> $2"
}
plainmv() {
  [ -e "$1" ] || { echo "  uebersprungen (fehlt): $1"; return 0; }
  git mv "$1" "$2"
  echo "  $1 -> $2"
}

casemv "chocks-Info.plist"                  "Chocks-Info.plist"
casemv "chocks.entitlements"                "Chocks.entitlements"
casemv "chocks WidgetExtension.entitlements" "Chocks WidgetExtension.entitlements"
casemv "chocks Widget"                      "Chocks Widget"

plainmv "Chocks Widget/SkyScope_Widget.swift"             "Chocks Widget/ChocksWidget.swift"
plainmv "Chocks Widget/SkyScope_WidgetBundle.swift"       "Chocks Widget/ChocksWidgetBundle.swift"
plainmv "Chocks Widget/SkyScope_WidgetLiveActivity.swift" "Chocks Widget/ChocksWidgetLiveActivity.swift"
plainmv "Chocks Widget/SkyScope_WidgetControl.swift"      "Chocks Widget/ChocksWidgetControl.swift"

plainmv "SkyScope.xcodeproj" "Chocks.xcodeproj"
plainmv "Chocks.xcodeproj/xcshareddata/xcschemes/SkyScope.xcscheme" \
        "Chocks.xcodeproj/xcshareddata/xcschemes/Chocks.xcscheme"
plainmv "Chocks.xcodeproj/xcshareddata/xcschemes/SkyScope WidgetExtension.xcscheme" \
        "Chocks.xcodeproj/xcshareddata/xcschemes/Chocks WidgetExtension.xcscheme"

# xcuserdata ist gitignored - Xcode legt es neu an
rm -rf "Chocks.xcodeproj/xcuserdata"
rm -rf "Chocks.xcodeproj/project.xcworkspace/xcuserdata"

# ---------------------------------------------------------------------------
say "4/9  project.pbxproj"
# ---------------------------------------------------------------------------
PBX="Chocks.xcodeproj/project.pbxproj"
# Globales Rename: Targets, productName, Produkte, INFOPLIST_FILE,
# CODE_SIGN_ENTITLEMENTS (repariert die aktuell kaputten Pfade),
# Usage-Description-Text, Widget-DisplayName, Kommentare.
sed -i '' 's/SkyScope/Chocks/g' "$PBX"
# Kleingeschriebener Ordnername in der FileSystemSynchronizedRootGroup
sed -i '' 's/chocks Widget/Chocks Widget/g' "$PBX"
# Bundle-IDs explizit setzen (Variante A)
sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER = DK\.Chocks;/PRODUCT_BUNDLE_IDENTIFIER = ${APP_ID};/g" "$PBX"
sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER = \"DK\.Chocks\.Chocks-Widget\";/PRODUCT_BUNDLE_IDENTIFIER = \"${WIDGET_ID}\";/g" "$PBX"

grep -n 'PRODUCT_BUNDLE_IDENTIFIER' "$PBX" | sed 's/^/  /'

# ---------------------------------------------------------------------------
say "5/9  Schemes"
# ---------------------------------------------------------------------------
sed -i '' 's/SkyScope/Chocks/g' Chocks.xcodeproj/xcshareddata/xcschemes/*.xcscheme

# ---------------------------------------------------------------------------
say "6/9  Chocks-Info.plist (PlistBuddy - URL-Scheme bleibt klein!)"
# ---------------------------------------------------------------------------
PB=/usr/libexec/PlistBuddy
$PB -c "Set :CFBundleDisplayName Chocks" "Chocks-Info.plist"
$PB -c "Set :CFBundleName Chocks"        "Chocks-Info.plist"
$PB -c "Set :NSCameraUsageDescription 'Chocks uses the camera to align nearby aircraft with the sky in AR.'" "Chocks-Info.plist"
$PB -c "Set :NSLocationWhenInUseUsageDescription 'Chocks uses your location to find aircraft flying near you.'" "Chocks-Info.plist"
$PB -c "Set :NSLocationAlwaysAndWhenInUseUsageDescription 'Chocks uses your location to find aircraft nearby, including while the screen is locked so Live Activities can keep updating.'" "Chocks-Info.plist"
echo "  unveraendert: CFBundleURLSchemes=chocks, com.chocks.app, com.chocks.bgrefresh"

# ---------------------------------------------------------------------------
say "7/9  Swift-Quellcode"
# ---------------------------------------------------------------------------
# Nutzerlesbarer Fliesstext - diese drei Dateien enthalten keine Identifier
sed -i '' 's/\bchocks\b/Chocks/g' Views/HelpView.swift Views/OnboardingView.swift Views/FeedbackView.swift
# Anzeigetext der Live Activity
sed -i '' 's/userLocation: "chocks"/userLocation: "Chocks"/g' \
  LiveActivityManager.swift "Chocks Widget/ChocksWidgetLiveActivity.swift"
# Header-Kommentare
sed -i '' 's|^//  chocks Widget|//  Chocks Widget|' "Chocks Widget"/*.swift
sed -i '' 's|Manages the single chocks Live Activity|Manages the single Chocks Live Activity|' LiveActivityManager.swift

# Erklaerender Kommentar am Legacy-Keychain-Service (bleibt DK.SkyScope!)
if ! grep -q "Alter Bundle-Identifier" Models/AppSettings.swift; then
  sed -i '' 's|private nonisolated static let legacyKeychainService = "DK.SkyScope"|// Alter Bundle-Identifier vor der Umbenennung auf Chocks -\
    // NICHT aendern, migriert bestehende Keychain-Eintraege.\
    private nonisolated static let legacyKeychainService = "DK.SkyScope"|' Models/AppSettings.swift
fi

# ---------------------------------------------------------------------------
say "8/9  Nebendateien"
# ---------------------------------------------------------------------------
sed -i '' 's|Projects/SkyScope|Projects/Chocks|g; s/SkyScopeApp\.swift/ChocksApp.swift/g; s/scheme SkyScope/scheme Chocks/g; s/SkyScope\.xcodeproj/Chocks.xcodeproj/g' \
  .claude/settings.local.json
sed -i '' 's/chocksActivityAttributes\.swift/ChocksActivityAttributes.swift/' CLAUDE.md

# ---------------------------------------------------------------------------
say "9/9  Verifikation"
# ---------------------------------------------------------------------------
echo "  Restliche SkyScope-Treffer (erwartet: AppSettings.swift + GoogleService-Info.plist):"
grep -ri skyscope . --exclude-dir=.git --exclude-dir=xcuserdata --exclude-dir=DerivedData | sed 's/^/    /' || true

echo
echo "  Clean Build gegen Simulator:"
xcodebuild -project Chocks.xcodeproj -scheme Chocks \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -configuration Debug clean build

echo
echo "  Widget-Target:"
xcodebuild -project Chocks.xcodeproj -scheme 'Chocks WidgetExtension' \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -configuration Debug build

# ---------------------------------------------------------------------------
say "Fertig - Aenderungen sind NICHT committet"
# ---------------------------------------------------------------------------
cat <<'EOF'
Wenn der Build gruen ist:

  git add -A
  git commit -m "Rename SkyScope to Chocks

  - Projekt, Targets, Schemes und Produkte auf Chocks umgestellt
  - Bundle-IDs auf com.puffblende.chocks(.widget) gewechselt
  - Info.plist- und Entitlements-Pfade repariert (zeigten ins Leere)
  - Anzeigename und nutzerlesbare Texte vereinheitlicht
  - Ungenutzte LiveActivityManager-Kopien entfernt

  Reverse-DNS-Identifier (chocks://, com.chocks.*, App Group) bleiben klein.
  legacyKeychainService bleibt DK.SkyScope fuer die Migration."

Nicht pushen. Ordner-Rename (~/Projects/SkyScope -> Chocks) separat als letzter Schritt.
EOF
