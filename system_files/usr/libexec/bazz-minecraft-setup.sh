#!/bin/bash
set -euo pipefail
umask 077

stamp=/var/lib/bazz-emu-inf/minecraft-setup
mkdir -p "$(dirname "$stamp")" /etc/minecraft

if [ ! -f /etc/minecraft/env ]; then
    rcon=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
    { echo "RCON_PASSWORD=$rcon"; echo "PLAYIT_SECRET_KEY="; } > /etc/minecraft/env
elif [ -z "$(awk -F= '$1 == "RCON_PASSWORD" { value = substr($0, index($0, "=") + 1) } END { print value }' /etc/minecraft/env)" ]; then
    rcon=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
    tmp=$(mktemp /etc/minecraft/env.XXXXXX)
    grep -v '^RCON_PASSWORD=' /etc/minecraft/env > "$tmp" || true
    echo "RCON_PASSWORD=$rcon" >> "$tmp"
    mv "$tmp" /etc/minecraft/env
fi
grep -q '^PLAYIT_SECRET_KEY=' /etc/minecraft/env || echo 'PLAYIT_SECRET_KEY=' >> /etc/minecraft/env
chown root:root /etc/minecraft/env
chmod 0600 /etc/minecraft/env

if [ ! -f /etc/minecraft/pack.env ]; then
    # Preserve the only pack controls emitted by older image versions. The
    # dedicated file is loaded last, so these safely override legacy copies.
    grep -E '^(TYPE|VERSION|MEMORY)=' /etc/minecraft/env > /etc/minecraft/pack.env || true
    grep -q '^TYPE=' /etc/minecraft/pack.env || echo 'TYPE=VANILLA' >> /etc/minecraft/pack.env
    grep -q '^VERSION=' /etc/minecraft/pack.env || echo 'VERSION=LATEST' >> /etc/minecraft/pack.env
    grep -q '^MEMORY=' /etc/minecraft/pack.env || echo 'MEMORY=4G' >> /etc/minecraft/pack.env
fi
chown root:root /etc/minecraft/pack.env
chmod 0600 /etc/minecraft/pack.env

[ -f "$stamp" ] && exit 0

firewall-cmd --permanent --add-port=25565/tcp
firewall-cmd --reload

touch "$stamp"
