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

# ES-DE: gamelists + settings (Linux data dir is ~/.emulationstation)
push esde /home/shrinksenpai/.emulationstation

# RetroArch flatpak: config, saves, states, system (BIOS dumps)
push retroarch /home/shrinksenpai/.var/app/org.libretro.RetroArch/config/retroarch

# Steam userdata (Bazzite ships Steam natively); adopt-or-create on next launch
push steam-userdata /home/shrinksenpai/.local/share/Steam/userdata

# Sunshine: apps.json (per-game entries) + sunshine.conf only — the freshly
# bootstrapped credentials and sunshine_state.json stay as they are.
echo "== restore: sunshine apps.json + sunshine.conf"
ssh "$BOX" "mkdir -p /home/shrinksenpai/.config/sunshine"
scp -q "$STAGE/sunshine-config/apps.json" "$STAGE/sunshine-config/sunshine.conf" \
    "$BOX:/home/shrinksenpai/.config/sunshine/"
ssh "$BOX" "sudo chown shrinksenpai:shrinksenpai /home/shrinksenpai/.config/sunshine/apps.json /home/shrinksenpai/.config/sunshine/sunshine.conf && sudo systemctl restart sunshine"

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

# ES-DE downloaded media (8.9 GB, lives only on the NAS) -> ~/ROMs/<system>/
# ES-DE expects each system's media under the ROMs root as downloaded_media.
# Streamed proxmox -> box directly: staging it on .51 would eat ~18 GB of the
# small root disk (learned the hard way — 2026-08-30).
echo "== restore: ES-DE downloaded media (this is the big one)"
ssh "$BOX" "rm -rf /var/tmp/esde-media && mkdir -p /var/tmp/esde-media /home/shrinksenpai/ROMs"
ssh proxmox "cat $PVE_DIR/esde-media.tar" | ssh "$BOX" "tar xf - -C /var/tmp/esde-media"
ssh "$BOX" 'for sys in /var/tmp/esde-media/downloaded_media/*/; do
    name=$(basename "$sys")
    mkdir -p "/home/shrinksenpai/ROMs/$name"
    rm -rf "/home/shrinksenpai/ROMs/$name/downloaded_media"
    mv "$sys" "/home/shrinksenpai/ROMs/$name/downloaded_media"
done
rm -rf /var/tmp/esde-media
sudo chown -R shrinksenpai:shrinksenpai /home/shrinksenpai/ROMs'

echo "== done. Owner verification: launch ES-DE, Steam, and a Moonlight session."
