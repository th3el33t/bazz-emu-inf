#!/bin/bash
# First-boot installer for the emulation Flatpaks. Idempotent: stamps on success
# and only stamps on success, so a failed run (e.g. no network) retries next boot.
set -euo pipefail

stamp=/var/lib/bazz-emu-inf/flatpaks-installed
list=/usr/share/bazz-emu-inf/flatpaks-emulation.list

mkdir -p "$(dirname "$stamp")"
[ -f "$stamp" ] && exit 0

flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

mapfile -t apps < <(grep -vE '^\s*(#|$)' "$list")
if [ "${#apps[@]}" -gt 0 ]; then
    flatpak install -y --noninteractive flathub "${apps[@]}"
fi

touch "$stamp"
