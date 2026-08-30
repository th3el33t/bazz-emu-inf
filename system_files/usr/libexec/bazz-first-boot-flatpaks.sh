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
failed=0
for app in "${apps[@]}"; do
    if ! flatpak install -y --noninteractive flathub "$app"; then
        echo "WARNING: failed to install $app" >&2
        failed=1
    fi
done
# Only stamp when every listed app installed, so a failure retries next boot.
if [ "$failed" -ne 0 ]; then
    exit 1
fi

touch "$stamp"
