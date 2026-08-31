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

# Sunshine game streaming: native RPM from the official LizardByte COPR (the
# Flathub Flatpak is sandboxed away from setcap and therefore can't do KMS
# capture). KMS needs cap_sys_admin on the binary and nvidia-drm.modeset=1
# (kargs.d drop-in); virtual input needs the udev rule + input group, which the
# system service grants via SupplementaryGroups.
dnf5 -y copr enable lizardbyte/stable
dnf5 -y install Sunshine
setcap cap_sys_admin+p /usr/bin/sunshine
chmod +x /usr/libexec/bazz-sunshine-bootstrap.sh
chmod +x /usr/share/bazz-emu-inf/sunshine/hooks/stream-start.sh
chmod +x /usr/share/bazz-emu-inf/sunshine/hooks/stream-end.sh
systemctl enable bazz-sunshine-bootstrap.service
systemctl enable sunshine.service

# Local inference: llama-swap (on-demand Qwen3-Coder-30B-A3B-Instruct behind a
# wake gate) as a podman quadlet. Weights are the data layer — download-models.sh
# fetches them from HuggingFace on first boot via the Xet backend below.
#
# huggingface_hub + hf_xet, system-wide in /usr, so the first-boot service execs
# /usr/bin/python3 with a normal SELinux context (a user-installed hf under
# /root/.local is blocked from systemd exec). Xet gives ~40x over plain curl.
dnf5 -y install python3-pip
pip install --prefix=/usr --break-system-packages huggingface_hub hf_xet
chmod +x /usr/libexec/bazz-llama/gpu-busy.sh
chmod +x /usr/libexec/bazz-llama/qwen-wake.sh
chmod +x /usr/libexec/bazz-llama/download-models.sh
chmod +x /usr/libexec/bazz-llama/gpu-arbiter.sh
systemctl enable bazz-llama-models.service
# Evicts a resident model the moment a human workload claims the card (the
# Windows VRAM-Reclaim replacement). Reuses gpu-busy.sh as the busy predicate.
systemctl enable bazz-gpu-arbiter.service

# Minecraft: itzg server + playit tunnel + mc-backup as quadlets on host
# networking; private runtime env + pack selection generated separately on-box;
# world data under /var/lib/minecraft (data layer).
chmod +x /usr/libexec/bazz-minecraft-setup.sh
systemctl enable bazz-minecraft-setup.service
