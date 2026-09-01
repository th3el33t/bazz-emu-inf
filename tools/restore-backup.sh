#!/bin/bash
# restore-backup.sh — push the migration backup + emulation library onto the
# Bazzite box. Run from cc-homelab (.51):
#
#   ( set -eu
#     : "${BOX:?}"      # e.g. BOX=waterdemon
#     tools/restore-backup.sh )
#
# Config/saves come from the migration tar on the NAS (via Proxmox). The
# emulation library (ROMs, gamelists, BIOS) comes from the NAS ROMS share, which
# the box NFS-mounts directly. Idempotent (rsync without --delete). Not an image
# layer — this restores the DATA layer (two-layer rule).
set -euo pipefail

BOX=${BOX:-waterdemon}
STAGE=/var/tmp/wd-restore-staging
BACKUP_LOCAL=/var/tmp/wd-migration/wd-backup.tar.gz
PVE_DIR=/mnt/pve/synology-vzdump/archive/waterdemon-migration-2026-08-30

mkdir -p "$STAGE"

SECTION=${1:-all}


# --- fetch the config backup if not local
if [ ! -f "$BACKUP_LOCAL" ]; then
    echo "fetching wd-backup.tar.gz from proxmox"
    ssh proxmox "cat $PVE_DIR/wd-backup.tar.gz" > "$BACKUP_LOCAL"
fi

[ "$SECTION" = all ] || [ "$SECTION" = config ] || { [ "$SECTION" = media ] && SKIP_CONFIG=1; }
if [ "${SKIP_CONFIG:-0}" = 0 ]; then
echo "== extracting config backup"
tar xzf "$BACKUP_LOCAL" -C "$STAGE"

push() { # push <staging-path> <box-dest> — as shrinksenpai, then fix ownership
    local src=$1 dest=$2
    echo "== restore: $src -> $dest"
    ssh "$BOX" "mkdir -p '$dest'"
    rsync -a "$STAGE/$src/" "$BOX:$dest/"
    ssh "$BOX" "sudo chown -R shrinksenpai:shrinksenpai '$dest'"
}

# RetroArch flatpak: saves/states from the migration backup. (Cores + BIOS are
# installed fresh below — do NOT expect the Windows retroarch.cfg here to be
# valid on Linux; ES-DE drives core selection.)
push retroarch /home/shrinksenpai/.var/app/org.libretro.RetroArch/config/retroarch

# Steam userdata (Bazzite ships Steam natively); adopt-or-create on next launch
push steam-userdata /home/shrinksenpai/.local/share/Steam/userdata

# Sunshine config is NO LONGER restored here. The Windows-era apps.json +
# sunshine.conf in the backup drive the (Windows-only) VDD/dd_* + PowerShell
# path and would clobber the Linux virtual-display setup. The canonical Linux
# sunshine.conf/apps.json + Sunveil hooks now ship in the image (seeded into
# ~/.config/sunshine by bazz-sunshine-bootstrap.sh). See README "Headless
# streaming". Restoring them from the migration tar is intentionally dropped.

# Minecraft world: extract the world tar into the quadlet's data dir.
echo "== restore: minecraft world"
tar tzf "$STAGE/minecraft/minecraft-world.tar.gz" >/dev/null  # sanity: readable tar
scp -q "$STAGE/minecraft/minecraft-world.tar.gz" "$BOX:/tmp/minecraft-world.tar.gz"
# The tar wraps the whole /opt/minecraft tree (compose.yaml + data/) — flatten
# so the world lands directly in the quadlet's data dir.
ssh "$BOX" "sudo mkdir -p /var/lib/minecraft/data &&
            sudo tar xzf /tmp/minecraft-world.tar.gz -C /var/lib/minecraft/data &&
            sudo bash -c 'shopt -s dotglob; mv /var/lib/minecraft/data/data/* /var/lib/minecraft/data/ &&
                            rmdir /var/lib/minecraft/data/data; rm -f /var/lib/minecraft/data/compose.yaml' &&
            sudo chown -R 1000:1000 /var/lib/minecraft/data &&
            rm /tmp/minecraft-world.tar.gz"

fi

# --- ES-DE emulation library (ROMs + gamelists + media + BIOS + cores) --------
# ES-DE 3.4 reads ~/ES-DE (NOT the legacy ~/.emulationstation, and NOT
# ~/.config/ES-DE). The ROM library + curated metadata + BIOS live on the NAS
# (192.168.86.245:/volume1/ROMS, exported to the box); the 8.9 GB of scraped
# media is streamed from the migration tar. Layout mirrors the gtr9 rig
# documented in ROMS/Curated/RESTORE.md.
echo "== restore: ES-DE downloaded media (8.9 GB) -> ~/ES-DE/downloaded_media"
# Stream the tar straight to the box (staging on .51 would eat ~18 GB of the
# small root disk — learned 2026-08-30). Media goes to <MediaDir>/<system>/,
# where MediaDir defaults to ~/ES-DE/downloaded_media — NOT under ~/ROMs.
ssh "$BOX" "rm -rf /var/tmp/esde-media && mkdir -p /var/tmp/esde-media /home/shrinksenpai/ES-DE/downloaded_media"
ssh proxmox "cat $PVE_DIR/esde-media.tar" | ssh "$BOX" "tar xf - -C /var/tmp/esde-media"
ssh "$BOX" 'for sys in /var/tmp/esde-media/downloaded_media/*/; do
    name=$(basename "$sys")
    rm -rf "/home/shrinksenpai/ES-DE/downloaded_media/$name"
    mv "$sys" "/home/shrinksenpai/ES-DE/downloaded_media/$name"
done
rm -rf /var/tmp/esde-media
sudo chown -R shrinksenpai:shrinksenpai /home/shrinksenpai/ES-DE'

echo "== restore: ROMs + gamelists + BIOS + libretro cores (from NAS ROMS)"
# All of this runs on the box: it NFS-mounts the NAS ROMS share and works from
# there. rsync runs as shrinksenpai — the Synology squashes root, so a root
# rsync of the share fails Permission denied.
ssh "$BOX" 'set -e
NAS=192.168.86.245:/volume1/ROMS
MNT=/mnt/nas-roms
sudo mkdir -p "$MNT"
mountpoint -q "$MNT" || sudo mount -t nfs -o ro,soft,timeo=100 "$NAS" "$MNT"

H=/home/shrinksenpai
RA="$H/.var/app/org.libretro.RetroArch/config/retroarch"
PCSX2="$H/.var/app/net.pcsx2.PCSX2/config/PCSX2/bios"
DS="$H/.local/share/duckstation/bios"

# ROMs: ~80 GB curated 1g1r set. Exclude any media/gamelists baked alongside.
sudo -u shrinksenpai rsync -a --exclude=downloaded_media --exclude=gamelist.xml \
    "$MNT/Curated/roms/" "$H/ROMs/"

# gamelists + collections (coherent with the curated ROM set)
sudo -u shrinksenpai mkdir -p "$H/ES-DE/gamelists" "$H/ES-DE/collections"
sudo -u shrinksenpai cp -a "$MNT/Curated/metadata/gamelists/." "$H/ES-DE/gamelists/"
sudo -u shrinksenpai cp -a "$MNT/Curated/metadata/collections/." "$H/ES-DE/collections/" 2>/dev/null || true

# The curated gamelists/collections were authored on the gtr9 rig with ABSOLUTE
# /srv/roms/<system>/... paths baked into every <path>/<rom> entry. This box keeps
# ROMs under ~/ROMs (see ROMDirectory below), so without rewriting the prefix ES-DE
# resolves ZERO gamelist entries — it still shows the games (from the ROM scan) but
# drops all scraped names/metadata/artwork. That is the "import failed" symptom.
# Media resolves by ROM basename, so a prefix rewrite is all that's needed.
sudo -u shrinksenpai find "$H/ES-DE/gamelists" "$H/ES-DE/collections" -type f \
    \( -name "*.xml" -o -name "*.cfg" \) -exec sed -i "s|/srv/roms/|$H/ROMs/|g" {} +

# BIOS -> RetroArch system + DuckStation (PS1) + PCSX2 (PS2)
sudo -u shrinksenpai mkdir -p "$RA/system" "$DS" "$PCSX2"
sudo -u shrinksenpai cp -a "$MNT/Curated/BIOS/." "$RA/system/"
for b in "$MNT"/Curated/BIOS/scph550?.bin; do [ -e "$b" ] && sudo -u shrinksenpai cp -a "$b" "$DS/"; done
[ -f "$RA/system/ps2-0230a-20080220.bin" ] && sudo -u shrinksenpai cp -a "$RA/system/ps2-0230a-20080220.bin" "$PCSX2/" || true

# libretro cores — ES-DE defaults for the systems present, from the buildbot
CORES="$RA/cores"; BB=https://buildbot.libretro.com/nightly/linux/x86_64/latest
sudo -u shrinksenpai mkdir -p "$CORES"
for c in snes9x mesen gambatte mgba genesis_plus_gx picodrive mupen64plus_next \
         mednafen_pce mednafen_supergrafx mednafen_wswan mednafen_ngp mednafen_vb \
         handy stella a5200 prosystem pokemini mednafen_psx_hw; do
    [ -f "$CORES/${c}_libretro.so" ] && continue
    if curl -fsSL "$BB/${c}_libretro.so.zip" -o /tmp/$c.zip 2>/dev/null; then
        sudo -u shrinksenpai unzip -o /tmp/$c.zip -d "$CORES" >/dev/null 2>&1 || true
    fi
    rm -f /tmp/$c.zip
done

# point ES-DE at the ROM dir (empty value shows "no games / import failed")
sudo -u shrinksenpai sed -i \
    "s|<string name=\"ROMDirectory\" value=\"[^\"]*\" />|<string name=\"ROMDirectory\" value=\"$H/ROMs\" />|" \
    "$H/ES-DE/settings/es_settings.xml"

sudo chown -R shrinksenpai:shrinksenpai "$H/ROMs" "$H/ES-DE"
sudo umount "$MNT" 2>/dev/null || true
echo "ES-DE restore complete"
'

echo "== done. Owner verification: launch ES-DE, Steam, and a Moonlight session."
