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
# Installs the emulation apps on first boot, then stamps itself done. Keeps the
# image slim and the apps user-updatable. Flatpaks for what Flathub carries
# (RetroArch, PCSX2); AppImages for what it doesn't (ES-DE, DuckStation).
chmod +x /usr/libexec/bazz-first-boot-flatpaks.sh
chmod +x /usr/libexec/bazz-first-boot-appimages.sh
systemctl enable bazz-first-boot-flatpaks.service
systemctl enable bazz-first-boot-appimages.service

# Monitoring: node_exporter runs as a podman quadlet (self-enabling via its
# [Install] section); the GPU textfile timer feeds it nvidia_gpu_* metrics.
chmod +x /usr/libexec/bazz-gpu-textfile.sh
systemctl enable bazz-gpu-textfile.timer
