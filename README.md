# bazz-emu-inf

Custom [bootc](https://containers.github.io/bootc/) OS image for **WaterDemon** — the
homelab's bare-metal RTX 4090 / Ryzen 9 7950X box — built on
[Bazzite](https://bazzite.gg) (`bazzite-nvidia-open`). It replaces a fragile Windows 11
install with an immutable, image-based, rollback-able OS that stays current on its own.

Published image: `ghcr.io/th3el33t/bazz-emu-inf:latest`

## Why this exists

WaterDemon runs game streaming, retro emulation, local LLM inference, transcription and a
Minecraft server. On Windows that meant a nightly reboot, a smart-plug freeze watchdog, and
a pile of PowerShell band-aids for VDD/`pnputil`, dwm VRAM leaks and WSL port theft. This
image moves the whole thing to Linux, where:

- updates are **atomic** — `bootc upgrade` swaps the image; `bootc rollback` reverts the
  entire OS + customizations in one step if an update misbehaves;
- the OS is **declarative** — everything below is code in this repo, rebuilt nightly by CI
  **on top of upstream Bazzite**, so gaming/NVIDIA/kernel updates arrive without any merge
  maintenance.

## Two-layer design (important)

**Layer 1 — this image** carries only the OS plumbing: packages, systemd units, tuning,
podman quadlets and non-secret configs.

**Layer 2 — mutable data + containers**, never baked into the image:

| Never in the image | Lives instead in |
|---|---|
| Secrets / tokens | systemd credentials / env files on the box |
| Console **BIOS** files, **ROMs** | data dirs, restored from backup / NAS |
| Model weights (GGUF), inference runtime | podman quadlet containers + a data volume |
| Saves, Minecraft world | data dirs, restored from the migration backup |

Keeping BIOS/ROMs/secrets out is also what makes publishing the image **public** safe.

## Roles (build-out status)

- [x] Base: `bazzite-nvidia-open` + CI + identity
- [x] Emulation apps: RetroArch + PCSX2 (first-boot Flatpaks); ES-DE + DuckStation (first-boot AppImages — neither exists on Flathub)
- [x] Monitoring: node_exporter quadlet (`:9100`) + `nvidia_gpu_*` textfile timer (replaces the Windows exporter; same metric names, homelab alert rules unchanged)
- [x] Sunshine streaming: native RPM (lizardbyte/stable COPR), system service, KMS capture, first-boot credential bootstrap — Moonlight pairing is the owner-verification step; per-stream gamescope app entries follow
- [x] Local inference: llama-swap quadlet (digest-pinned, llama.cpp b10689) + on-demand Qwen3.8-27B (120k ctx, q4_0 KV, MTP draft) with the `gpu-busy.sh` wake gate; weights download+sha256-verify at first boot. Full GPU arbitration (VRAM reclaim etc.) is its own item below
- [x] WhisperX transcription: Samba `[audio]` drop share (auth set by owner via `smbpasswd`) + path-unit sweep running one-shot `jim60105/whisperx:large-v3-en` containers, deferred by the shared `gpu-busy.sh` gate
- [x] Minecraft server: itzg (`:java21`) + playit + mc-backup quadlets on host net (`:25565`); env + RCON secret generated at first boot, playit starts once the owner drops its agent key in `/etc/minecraft/env`; world restore from the migration backup is the restore item below
- [ ] GPU arbitration (gate/VRAM logic rewritten from PowerShell to systemd)
- [ ] Config + save restore from the migration backup
- [ ] Cosign image signing

## Install

1. Boot a stock **Bazzite (KDE, NVIDIA)** USB and install to the NVMe (KDE-desktop
   autologin, **not** Steam Gaming Mode as default).
2. Rebase onto this image:
   ```
   sudo bootc switch ghcr.io/th3el33t/bazz-emu-inf:latest
   sudo systemctl reboot
   ```
3. Restore the data layer (ROMs, saves, world, configs, models) — see the migration runbook.

Updates thereafter: `sudo bootc upgrade` (or the built-in auto-updater). Roll back a bad
update: `sudo bootc rollback`.

## Build

CI (`.github/workflows/build.yml`) builds on every push to `main`, on PRs (build only, no
publish), and nightly at 10:05 UTC, rebasing on the latest upstream Bazzite. Base image
digest is pinned and bumped by renovate.
