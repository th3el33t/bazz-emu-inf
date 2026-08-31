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
systemctl enable bazz-sunshine-bootstrap.service
systemctl enable sunshine.service

# Local inference: llama-swap (on-demand Qwen3.8-27B behind a wake gate) as a
# podman quadlet. Weights are the data layer — download-models.sh fetches and
# sha256-verifies them from HuggingFace on first boot.
chmod +x /usr/libexec/bazz-llama/gpu-busy.sh
chmod +x /usr/libexec/bazz-llama/qwen-wake.sh
chmod +x /usr/libexec/bazz-llama/download-models.sh
systemctl enable bazz-llama-models.service

# WhisperX transcription: Samba [audio] drop share + a host-side path unit
# driving one-shot whisperx containers (the maintained image is CLI-only).
# GPU-busy defer reuses the inference layer's gpu-busy.sh predicate.
dnf5 -y install samba
systemctl enable smb.service
chmod +x /usr/libexec/bazz-samba-setup.sh
chmod +x /usr/libexec/bazz-llama/transcribe-pending.sh
systemctl enable bazz-samba-setup.service
systemctl enable bazz-whisperx.path
systemctl enable bazz-whisperx.timer

# Minecraft: itzg server + playit tunnel + mc-backup as quadlets on host
# networking; private runtime env + pack selection generated separately on-box;
# world data under /var/lib/minecraft (data layer).
chmod +x /usr/libexec/bazz-minecraft-setup.sh
systemctl enable bazz-minecraft-setup.service
