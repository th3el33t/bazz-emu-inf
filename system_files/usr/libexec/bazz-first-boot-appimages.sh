#!/bin/bash
# First-boot installer for the emulation apps that are NOT on Flathub:
#   - ES-DE       (frontend; AppImage from its GitLab releases)
#   - DuckStation (PS1 emulator; AppImage from GitHub releases)
# Both land in /usr/local/bin with .desktop entries, system-wide.
# Idempotent: stamps on full success only, so a partial failure retries next boot.
# Updates: pinned at first-boot versions by design; updating them is a deliberate
# follow-up (out of scope here — the apps own their configs either way).
set -euo pipefail

stamp=/var/lib/bazz-emu-inf/appimages-installed
bindir=/usr/local/bin
appsdir=/usr/local/share/applications

[ -f "$stamp" ] && exit 0
mkdir -p "$(dirname "$stamp")" "$bindir" "$appsdir"

# --- DuckStation: stable "latest" permalink from GitHub releases -------------
curl -fSL --retry 3 -o "$bindir/DuckStation.AppImage" \
    https://github.com/stenzek/duckstation/releases/download/latest/DuckStation-x64.AppImage
chmod +x "$bindir/DuckStation.AppImage"

cat > "$appsdir/duckstation.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=DuckStation
Comment=PlayStation 1 emulator
Exec=/usr/local/bin/DuckStation.AppImage
Terminal=false
Categories=Game;Emulator;
EOF

# --- ES-DE: resolve the latest GitLab release, pick the plain x64 AppImage ---
# (asset name is exactly ES-DE_x64.AppImage; the ES-DE_x64_SteamDeck.AppImage
# build is excluded by the exact-name match)
esde_url=$(curl -fsSL --retry 3 \
    "https://gitlab.com/api/v4/projects/es-de%2Femulationstation-de/releases" \
  | python3 -c '
import json, sys
releases = json.load(sys.stdin)
for rel in releases:
    for link in rel.get("assets", {}).get("links", []):
        if link.get("name") == "ES-DE_x64.AppImage":
            print(link["direct_asset_url"])
            sys.exit(0)
sys.exit("no ES-DE_x64.AppImage asset found in any release")
')
curl -fSL --retry 3 -o "$bindir/ES-DE.AppImage" "$esde_url"
chmod +x "$bindir/ES-DE.AppImage"

cat > "$appsdir/es-de.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=ES-DE
Comment=EmulationStation Desktop Edition frontend
Exec=/usr/local/bin/ES-DE.AppImage
Terminal=false
Categories=Game;Emulator;
EOF

update-desktop-database "$appsdir" 2>/dev/null || true
touch "$stamp"
