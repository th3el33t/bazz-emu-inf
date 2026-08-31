# bazz-emu-inf

Custom [bootc](https://containers.github.io/bootc/) OS image for **WaterDemon** — the
homelab's bare-metal RTX 4090 / Ryzen 9 7950X box — built on
[Bazzite](https://bazzite.gg) (`bazzite-nvidia-open`). It replaces a fragile Windows 11
install with an immutable, image-based, rollback-able OS that stays current on its own.

Published image: `ghcr.io/th3el33t/bazz-emu-inf:latest`

## Why this exists

WaterDemon runs game streaming, retro emulation, local LLM inference and a
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
- [x] Local inference: llama-swap quadlet (digest-pinned, llama.cpp b10689) + on-demand Qwen3-Coder-30B-A3B-Instruct (MoE 30B/3B-active, UD-Q4_K_XL, 160k ctx, q4_0 KV) with the `gpu-busy.sh` wake gate; weights download at first boot via the HuggingFace Xet backend (optional `HF_TOKEN` in `/etc/bazz-emu-inf/hf.env` lifts anonymous rate limits). Chosen for max token/s at good quality — replaced the dense Qwen3.8-27B on 2026-08-31 (benched ~211 tok/s decode on code, fits at 22913 MiB, vs the dense 49-83 tok/s); serves the opencode/omo `hephaestus` execution lane with `--parallel 2` (2×80k slots, VRAM-free split of the 160k ctx) so a delegated pair no longer serializes on the 4090. Full GPU arbitration (VRAM reclaim etc.) is its own item below
- [x] Minecraft server: itzg (`:java25`) + playit + mc-backup quadlets on host net (`:25565`); secrets live in `/etc/minecraft/env`, pack selection in `/etc/minecraft/pack.env`, and playit starts once the owner drops its agent key in the private env file
- [x] GPU arbitration: `gpu-arbiter.sh` service polls the shared `gpu-busy.sh` predicate and evicts a resident model (llama-swap `/unload`) within ~3 s of a stream/game/emulator claiming the card — the Windows VRAM-Reclaim replacement; the load-side gate (`qwen-wake.sh`) was already in the inference layer
- [x] Config + save restore: `tools/restore-backup.sh` (run from cc-homelab) pushes the migration backup into the data layer — ES-DE gamelists/settings + downloaded_media, RetroArch cfg/saves/BIOS, Steam userdata, Sunshine apps.json/sunshine.conf (not credentials), Minecraft world
- [x] Cosign image signing: keyless (Sigstore Fulcio + Rekor) via GH Actions OIDC on push to main + `v*` tags; workflow identity bound to `…/.github/workflows/build.yml@refs/heads/main`. Box-side enforcement via `/etc/containers/policy.json` (sigstoreSigned rule, keyPath `/etc/pki/containers/fulcio.pub` — public-good Fulcio root, sha256 `03:A3:8F:…D0`) + `enforce-container-sigpolicy = true` in `/usr/lib/bootc/install/90-bazz-emu-inf.toml`. `bootc upgrade` / `bootc switch` refuse unsigned images of this repo; mismatch rolls back to the previous signed deployment. SBOM attestation (CycloneDX) is a follow-up — syft disk quota on bootc images.

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

## Switch Minecraft packs

The container image is generic. `/etc/minecraft/pack.env` is the complete pack-selection
surface and accepts the pack-related environment variables supported by
[`itzg/minecraft-server`](https://docker-minecraft-server.readthedocs.io/). The separate
`/etc/minecraft/env` file contains the RCON password and playit key; pack changes must not
touch it. Do not put `RCON_PASSWORD` in `pack.env`: Minecraft loads that file last, while
the backup container reads only the private file. Use the native itzg names exactly; old
`MC_TYPE`/`MC_MEMORY`-style names are not recognized here.

Examples for `/etc/minecraft/pack.env`:

```dotenv
# Vanilla
TYPE=VANILLA
VERSION=LATEST
MEMORY=4G
```

```dotenv
# Modrinth, by slug, project ID, project URL, or .mrpack URL
TYPE=MODRINTH
MODRINTH_MODPACK=cobblemon-fabric
VERSION=LATEST
MEMORY=8G
```

For Modrinth, `VERSION` selects the modpack release rather than the base Minecraft version.

```dotenv
# CurseForge, by project or file URL
MODPACK_PLATFORM=AUTO_CURSEFORGE
CF_PAGE_URL=https://www.curseforge.com/minecraft/modpacks/all-the-mods-8
MEMORY=8G
```

```dotenv
# Packwiz; TYPE and VERSION must match the pack's pack.toml
TYPE=FABRIC
PACKWIZ_URL=https://example.com/modpack/pack.toml
VERSION=<minecraft version from pack.toml>
MEMORY=8G
```

Do a clean swap when moving between unrelated packs or Minecraft versions. Prepare the new
`pack.env` as a separate file, then move the current data aside as an immediate rollback
point. The regular backup container keeps only three rotating archives, so do not rely on it
as permanent protection for an old pack.

```bash
(
  set -eu
  NEW_PACK_ENV=
  : "${NEW_PACK_ENV:?set NEW_PACK_ENV to the prepared pack.env file}"
  swap_id=$(date -u +%Y%m%dT%H%M%SZ)
  base=/var/lib/minecraft

  sudo test -f "$NEW_PACK_ENV"
  sudo test ! -e "$base/data.pre-switch-$swap_id"
  sudo test ! -e "$base/modpacks.pre-switch-$swap_id"
  sudo systemctl stop mc-backup minecraft
  sudo install -o root -g root -m 0600 "$NEW_PACK_ENV" /etc/minecraft/pack.env
  sudo mv "$base/data" "$base/data.pre-switch-$swap_id"
  sudo mv "$base/modpacks" "$base/modpacks.pre-switch-$swap_id"
  sudo install -d -o 1000 -g 1000 -m 0755 "$base/data"
  sudo install -d -o root -g root -m 0755 "$base/modpacks"
  sudo systemctl start minecraft mc-backup
  sudo journalctl -u minecraft -f
)
```

Delete the `*.pre-switch-*` directories manually only after the new pack and world have
been validated. If any command before startup fails, the services remain stopped so the
moved directories can be restored without mixing installations.

For an in-place upgrade or downgrade of the same Modrinth pack, change its version selector
and restart without wiping first; the itzg image synchronizes that pack's managed files.

The default `java25` image supports current vanilla and modern packs. Java is selected by
container tag rather than an environment variable, so older packs need a local Quadlet
drop-in. This changes only the mutable host configuration; it does not rebuild the bootc
image.

```bash
sudo install -d /etc/containers/systemd/minecraft.container.d
printf '[Container]\nImage=docker.io/itzg/minecraft-server:java17\n' | \
  sudo tee /etc/containers/systemd/minecraft.container.d/10-java.conf >/dev/null
sudo systemctl daemon-reload
```

Replace `java17` with `java21` or `java8` as required by the pack. Auto CurseForge on images
older than Java 17 also needs `CF_API_KEY` in the root-only `pack.env`; preserve that key when
changing the other pack values. Remove the drop-in and reload systemd to return to the
image's `java25` default. Then perform the clean swap above.

## Build

CI (`.github/workflows/build.yml`) builds on every push to `main`, on PRs (build only, no
publish), and nightly at 10:05 UTC, rebasing on the latest upstream Bazzite. Base image
digest is pinned and bumped by renovate.
