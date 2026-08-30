#!/bin/bash

set -ouex pipefail

# Copy system_files/ into the image root.
cp -avf "/ctx/system_files"/. /

### OS-layer packages
# Only things that genuinely belong baked into the OS. GUI apps (emulators) are
# Flatpaks installed on first boot instead — see the first-boot service below.
# Big/fast-moving GPU stacks (llama.cpp, WhisperX) are podman quadlets, NOT here.
dnf5 install -y \
    tmux \
    htop

### Services
systemctl enable podman.socket
# Installs the emulation Flatpaks (ES-DE, RetroArch, DuckStation, PCSX2) on first
# boot, then stamps itself done. Keeps the image slim and the apps user-updatable.
chmod +x /usr/libexec/bazz-first-boot-flatpaks.sh
systemctl enable bazz-first-boot-flatpaks.service
