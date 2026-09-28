#!/bin/bash
# Installs build/Underdock.app into /Applications and cleans up after the
# earlier one-app-per-widget layout.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/Underdock.app"

[ -d "$APP" ] || { echo "Manca $APP — esegui prima ./build.sh"; exit 1; }

echo "→ chiudo le versioni in esecuzione"
# Solo quelle che stanno davvero girando: chiedere ad AppleScript di chiudere
# un'applicazione che non c'è più non dà errore — va a cercarla, e resta lì ad
# aspettare che qualcuno gliela indichi. I nomi vecchi sono quelli che questo
# progetto ha portato prima di chiamarsi Underdock.
quit_if_running() {
  pgrep -x "$1" >/dev/null 2>&1 || return 0
  osascript -e "quit app \"$1\"" 2>/dev/null || true
  # Chi non se ne va da solo entro qualche secondo va convinto.
  for _ in 1 2 3 4 5 6; do
    pgrep -x "$1" >/dev/null 2>&1 || return 0
    sleep 0.5
  done
  pkill -x "$1" 2>/dev/null || true
}

for name in DockClock DockNowPlaying Underdock "Dock Widgets" WidgetPro; do
  quit_if_running "$name"
done
# The overlay agent must go too, or the freshly installed one sees a duplicate
# of itself and quits.
pkill -f "NowPlayingBar.app/Contents/MacOS/NowPlayingBar" 2>/dev/null || true

echo "→ sistemo le voci del Dock"
defaults export com.apple.dock - | python3 -c '
import sys, plistlib
prefs = plistlib.loads(sys.stdin.buffer.read())

# Voci rimaste senza bundle dietro: vanno tolte.
stale = ("DockClock.app", "DockNowPlaying.app", "/dock/build/")

# Il nome e cambiato, i widget no. Riscrivere le voci invece di cancellarle
# tiene la disposizione che era stata scelta: cancellarle vuol dire rimettere
# ogni widget nel Dock a mano.
renames = (
    ("DockWidgets.app", "Underdock.app"),
    ("WidgetPro.app", "Underdock.app"),
    ("Application%20Support/DockWidgets/", "Application%20Support/Underdock/"),
    ("Application Support/DockWidgets/", "Application Support/Underdock/"),
    ("Application%20Support/WidgetPro/", "Application%20Support/Underdock/"),
    ("Application Support/WidgetPro/", "Application Support/Underdock/"),
    ("dev.nicolo.dockwidgets", "dev.nicolo.underdock"),
    ("dev.nicolo.widgetpro", "dev.nicolo.underdock"),
)

def url(entry):
    return entry.get("tile-data", {}).get("file-data", {}).get("_CFURLString", "")

def rename(entry):
    data = entry.get("tile-data")
    if not isinstance(data, dict):
        return
    target = data.get("file-data")
    if isinstance(target, dict) and isinstance(target.get("_CFURLString"), str):
        text = target["_CFURLString"]
        for before, after in renames:
            text = text.replace(before, after)
        target["_CFURLString"] = text
    identifier = data.get("bundle-identifier")
    if isinstance(identifier, str):
        for before, after in renames:
            identifier = identifier.replace(before, after)
        data["bundle-identifier"] = identifier

for key in ("persistent-apps", "persistent-others"):
    entries = prefs.get(key)
    if not entries:
        continue
    kept = [e for e in entries if not any(name in url(e) for name in stale)]
    for entry in kept:
        rename(entry)
    prefs[key] = kept
plistlib.dump(prefs, sys.stdout.buffer)
' | defaults import com.apple.dock -

echo "→ rimuovo i bundle vecchi"
rm -rf /Applications/DockClock.app /Applications/DockNowPlaying.app
rm -rf /Applications/DockWidgets.app /Applications/WidgetPro.app
# Le copie si rifanno da sole al primo avvio, sotto il nome nuovo.
rm -rf "$HOME/Library/Application Support/DockWidgets" \
       "$HOME/Library/Application Support/WidgetPro"

echo "→ installo Underdock.app"
# Swapped into place instead of removed and recopied: the Dock watches the
# files behind its tiles, and a bundle that disappears even for a moment gets
# its tiles dropped from the Dock at the next save.
rm -rf /Applications/Underdock.app.new
cp -R "$APP" /Applications/Underdock.app.new
if [ -d /Applications/Underdock.app ]; then
  mv /Applications/Underdock.app /Applications/Underdock.app.old
fi
mv /Applications/Underdock.app.new /Applications/Underdock.app
rm -rf /Applications/Underdock.app.old
touch /Applications/Underdock.app

# LaunchServices caches an app's Info.plist. Without this, a widget that gains
# a Dock tile plug-in keeps being loaded from the old description and the Dock
# never asks for the plug-in.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f /Applications/Underdock.app 2>/dev/null || true

killall -KILL Dock 2>/dev/null || true
open /Applications/Underdock.app
echo "Fatto."
