#!/bin/bash
# restore-backup.sh — push the Windows-era config/save migration backup onto
# the Bazzite box. Run from cc-homelab (.51):
#
#   ( set -eu
#     : "${BOX:?}"      # e.g. BOX=waterdemon
#     tools/restore-backup.sh )
#
# Sources (in order): /var/tmp/wd-migration on .51, else the NAS copy mounted
# on the Proxmox host. Idempotent: rsync without --delete, safe to re-run.
# Not an image layer — this restores the DATA layer (two-layer rule).
set -euo pipefail

BOX=${BOX:-waterdemon}
STAGE=/var/tmp/wd-restore-staging
BACKUP_LOCAL=/var/tmp/wd-migration/wd-backup.tar.gz
PVE_DIR=/mnt/pve/synology-vzdump/archive/waterdemon-migration-2026-08-30

mkdir -p "$STAGE"

# --- fetch the config backup if not local
if [ ! -f "$BACKUP_LOCAL" ]; then
    echo "fetching wd-backup.tar.gz from proxmox"
    ssh proxmox "cat $PVE_DIR/wd-backup.tar.gz" > "$BACKUP_LOCAL"
fi

echo "== extracting config backup"
tar xzf "$BACKUP_LOCAL" -C "$STAGE"

push() { # push <staging-path> <box-dest> — as shrinksenpai, then fix ownership
    local src=$1 dest=$2
    echo "== restore: $src -> $dest"
    ssh "$BOX" "mkdir -p '$dest'"
    rsync -a "$STAGE/$src/" "$BOX:$dest/"
    ssh "$BOX" "sudo chown -R shrinksenpai:shrinksenpai '$dest'"
}

# ES-DE: gamelists + settings (Linux data dir is ~/.emulationstation)
push esde ~shrinksenpai/.emulationstation

# RetroArch flatpak: config, saves, states, system (BIOS dumps)
push retroarch ~shrinksenpai/.var/app/org.libretro.RetroArch/config/retroarch

# Steam userdata (Bazzite ships Steam natively); adopt-or-create on next launch
push steam-userdata ~shrinksenpai/.local/share/Steam/userdata

# Sunshine: apps.json (per-game entries) + sunshine.conf only — the freshly
# bootstrapped credentials and sunshine_state.json stay as they are.
echo "== restore: sunshine apps.json + sunshine.conf"
ssh "$BOX" "mkdir -p ~shrinksenpai/.config/sunshine"
scp -q "$STAGE/sunshine-config/apps.json" "$STAGE/sunshine-config/sunshine.conf" \
    "$BOX:~shrinksenpai/.config/sunshine/"
ssh "$BOX" "sudo chown shrinksenpai:shrinksenpai ~shrinksenpai/.config/sunshine/apps.json ~shrinksenpai/.config/sunshine/sunshine.conf && sudo systemctl restart sunshine"

# Minecraft world: extract the world tar into the quadlet's data dir.
echo "== restore: minecraft world"
tar tzf "$STAGE/minecraft/minecraft-world.tar.gz" >/dev/null  # sanity: readable tar
scp -q "$STAGE/minecraft/minecraft-world.tar.gz" "$BOX:/tmp/minecraft-world.tar.gz"
ssh "$BOX" "sudo mkdir -p /var/lib/minecraft/data &&
            sudo tar xzf /tmp/minecraft-world.tar.gz -C /var/lib/minecraft/data &&
            sudo chown -R 1000:1000 /var/lib/minecraft/data &&
            rm /tmp/minecraft-world.tar.gz"

# ES-DE downloaded media (8.9 GB, lives only on the NAS) -> ~/ROMs/<system>/
# ES-DE expects each system's media under the ROMs root as downloaded_media.
echo "== restore: ES-DE downloaded media (this is the big one)"
ssh proxmox "cat $PVE_DIR/esde-media.tar" > /var/tmp/wd-migration/esde-media.tar
mkdir -p "$STAGE/media"
tar xf /var/tmp/wd-migration/esde-media.tar -C "$STAGE/media"
ssh "$BOX" "mkdir -p ~shrinksenpai/ROMs"
for sys in "$STAGE/media/downloaded_media"/*/; do
    name=$(basename "$sys")
    dest="~shrinksenpai/ROMs/$name/downloaded_media"
    echo "  media: $name"
    ssh "$BOX" "mkdir -p $dest"
    rsync -a "$sys" "$BOX:$dest/"
done
ssh "$BOX" "sudo chown -R shrinksenpai:shrinksenpai ~shrinksenpai/ROMs"

echo "== done. Owner verification: launch ES-DE, Steam, and a Moonlight session."
