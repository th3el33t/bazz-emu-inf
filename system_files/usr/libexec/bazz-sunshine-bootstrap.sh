#!/bin/bash
# One-shot: seed a random Sunshine web-UI admin credential on first boot, so the
# image itself carries no secret. The owner reads /etc/sunshine/bootstrap-password
# (root-only), logs into https://<host>:47990, and rotates the password there.
set -euo pipefail

stamp=/var/lib/bazz-emu-inf/sunshine-creds-seeded
[ -f "$stamp" ] && exit 0
mkdir -p "$(dirname "$stamp")" /etc/sunshine

# --- seed the Linux Sunshine config from the image templates -----------------
# The virtual-display streaming config lives in the DATA layer (user home), but
# the canonical Linux version ships in the image so a fresh install comes up
# correct instead of inheriting the Windows-era config. Per-file guards never
# clobber user edits (added games, tuning); the hook scripts are image-owned
# code and are always refreshed to match this image.
tmpl=/usr/share/bazz-emu-inf/sunshine
cfg=/home/shrinksenpai/.config/sunshine
install -d -o shrinksenpai -g shrinksenpai -m 0755 "$cfg" "$cfg/hooks"
[ -f "$cfg/sunshine.conf" ]      || install -o shrinksenpai -g shrinksenpai -m 0644 "$tmpl/sunshine.conf" "$cfg/sunshine.conf"
[ -f "$cfg/apps.json" ]          || install -o shrinksenpai -g shrinksenpai -m 0644 "$tmpl/apps.json" "$cfg/apps.json"
[ -f "$cfg/hooks/sunveil.conf" ] || install -o shrinksenpai -g shrinksenpai -m 0644 "$tmpl/hooks/sunveil.conf" "$cfg/hooks/sunveil.conf"
install -o shrinksenpai -g shrinksenpai -m 0755 "$tmpl/hooks/stream-start.sh" "$cfg/hooks/stream-start.sh"
install -o shrinksenpai -g shrinksenpai -m 0755 "$tmpl/hooks/stream-end.sh"   "$cfg/hooks/stream-end.sh"

user=shrinksenpai
pass=$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 24 || true)
[ -n "$pass" ] || { echo "password generation produced empty string" >&2; exit 1; }

# --creds can keep running the server after writing credentials; bound it and
# only require that the state file appears.
timeout 30 runuser -u "$user" -- env HOME=/home/"$user" \
    /usr/bin/sunshine --creds sunshine-admin "$pass" || true
state=/home/$user/.config/sunshine/sunshine_state.json
[ -s "$state" ] || { echo "sunshine --creds did not write $state" >&2; exit 1; }

install -m 0600 -o root -g root /dev/null /etc/sunshine/bootstrap-password
printf 'user: sunshine-admin\npassword: %s\n' "$pass" > /etc/sunshine/bootstrap-password
touch "$stamp"
