#!/bin/bash
# One-shot: /etc/minecraft/env (random RCON password, blank playit secret) and
# the firewall rule for :25565 (below Bazzite's open 1025-65535 game range).
set -euo pipefail

stamp=/var/lib/bazz-emu-inf/minecraft-setup
[ -f "$stamp" ] && exit 0
mkdir -p "$(dirname "$stamp")" /etc/minecraft

if [ ! -f /etc/minecraft/env ]; then
    rcon=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
    { echo "RCON_PASSWORD=$rcon"; echo "PLAYIT_SECRET_KEY=";
      echo "TYPE=VANILLA"; echo "VERSION=LATEST"; echo "MEMORY=4G"; } > /etc/minecraft/env
    chmod 0600 /etc/minecraft/env
fi

firewall-cmd --permanent --add-port=25565/tcp
firewall-cmd --reload

touch "$stamp"
