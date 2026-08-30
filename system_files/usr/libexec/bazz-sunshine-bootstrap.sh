#!/bin/bash
# One-shot: seed a random Sunshine web-UI admin credential on first boot, so the
# image itself carries no secret. The owner reads /etc/sunshine/bootstrap-password
# (root-only), logs into https://<host>:47990, and rotates the password there.
set -euo pipefail

stamp=/var/lib/bazz-emu-inf/sunshine-creds-seeded
[ -f "$stamp" ] && exit 0
mkdir -p "$(dirname "$stamp")" /etc/sunshine

user=shrinksenpai
pass=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)

# --creds can keep running the server after writing credentials; bound it and
# only require that the state file appears.
timeout 30 runuser -u "$user" -- env HOME=/home/"$user" \
    /usr/bin/sunshine --creds sunshine-admin "$pass" || true
state=/home/$user/.config/sunshine/sunshine_state.json
[ -s "$state" ] || { echo "sunshine --creds did not write $state" >&2; exit 1; }

install -m 0600 -o root -g root /dev/null /etc/sunshine/bootstrap-password
printf 'user: sunshine-admin\npassword: %s\n' "$pass" > /etc/sunshine/bootstrap-password
touch "$stamp"
