# AGENTS.md

> Instructions for AI coding agents working on this repo. Read this before making changes.
> `README.md` is the authoritative *product* documentation and is unusually complete — read it
> for what the image does and why. This file carries only what an agent needs that the README
> does not say.

## ⛔ The target machine is not running

This repo builds a bootc OS image for **WaterDemon** (`192.168.86.40`), the bare-metal
RTX 4090 / Ryzen 9 7950X box. **WaterDemon has been dead since 2026-09-08** — it will not POST
and is out for warranty. Probed 2026-09-14: `192.168.86.40` is *no route to host*.

Consequences that decide how you work here:

- **You cannot test anything on the box.** No `bootc switch`, no `bootc upgrade`, no "check it
  on the host". CI and a local VM (`just build-qcow2` / `just spawn-vm`) are the only feedback
  available, and neither exercises the NVIDIA/Sunshine/streaming paths that matter most.
- **The image is still built nightly** (`.github/workflows/build.yml`, cron `05 10 * * *` UTC)
  and published to `ghcr.io/th3el33t/bazz-emu-inf:latest`. That is deliberate — the point is
  that the image stays current so the box can be re-imaged when it returns, not that anything
  consumes it today.
- **Recent work is re-install preparation**, not runtime work: the 2026-09-11 commits fixed the
  `build-disk` / anaconda-ISO leg. That is the path that gets a warranty-returned box back to
  this image, so treat it as load-bearing.
- **The four CPU services WaterDemon used to host moved to `cpu-svc` (`192.168.86.74`,
  LXC 123)** — `kokoro-tts` :8092, `fwhisper` :8090, `supertonic-tts` :7788, `hound` :8765 —
  and its `qwen3-coder-30b-a3b` inference lane on :8085 was **killed, not paused**. Anything
  elsewhere in the estate still pointing at WaterDemon for speech or inference is broken, not
  merely idle. Do not "fix" those consumers by pointing them back here.

⚠️ **Do not silently repurpose this image for another host.** Almost everything in it is
WaterDemon-shaped: NVIDIA-open, the LG C9 capture workaround, the 4090 VRAM arbitration, the
Game Den layout. A different box is a new image, not a flag.

## Hard rules

1. **Never bake a secret, ROM, BIOS file, save, world or model weight into the image.** The
   two-layer split in the README is what makes publishing to a *public* registry safe. Layer 1
   (this repo) is OS plumbing only: packages, units, tuning, quadlets, non-secret config.
   Anything with a licence problem or a credential lives on the box, in a data dir or a
   systemd credential.
2. **`/etc/minecraft/pack.env` and `/etc/minecraft/env` are different files on purpose.**
   `pack.env` is pack selection and is safe to edit; `env` holds the RCON password and playit
   key. ⚠️ **Never put `RCON_PASSWORD` in `pack.env`** — Minecraft loads it last and would win,
   while the backup container reads only the private file, so backups would silently start
   failing to authenticate. Use itzg's native variable names exactly; `MC_TYPE` /
   `MC_MEMORY`-style names are not recognised.
3. **Do not switch Sunshine back to KMS capture.** Capture is `capture = kwin` through a
   `krfb-virtualmonitor` spun up by a `global_prep_cmd` hook. This is not a style preference:
   on Linux/NVIDIA the LG C9 drops its DRM output the moment it sleeps (nvidia-drm honours no
   `edid_firmware`), so KMS capture of the physical panel dies with the TV — which is the
   entire headless-streaming use case.
4. **Auto-suspend stays disabled image-wide** (`sleep.conf.d`). A headless box that suspends on
   idle falls off the network and is indistinguishable from a hard freeze; the HA Zigbee-plug
   watchdog is last-resort recovery, not the design.
5. **Cosign box-side enforcement is OFF deliberately**, and the reason is documented in the
   README (private GitHub email → no `email` SAN in the Fulcio cert → the box rejects its own
   correctly-signed image). CI still signs keyless on every push and the trust anchors ship in
   the image. Don't "fix" `policy.json` to `sigstoreSigned` without first making
   email-visibility public — you would brick updates on a box that cannot currently be
   recovered by hand.

## Working in here

- **Landing:** GitHub (`github.com/th3el33t/bazz-emu-inf`), default branch `main`. Worktree →
  PR → `gh pr merge --merge`. The user-global concurrent-session workflow applies in full.
- **Local checks before merging:** `just check` / `just lint` / `just format`. CI is the real
  gate for image builds; a local `just build` needs podman and pulls the Bazzite base.
- **Dependabot** keeps the GitHub-Actions pins current and opens PRs here routinely. Those are
  ordinary small PRs, not noise — a pinned action that dies on a newer runner has already
  broken the disk-image leg once (2026-09-11).
- `image-template.env` is the single source for image name/org/description; the `Justfile`
  reads it via `set dotenv-filename`. Change values there, not in recipes.

## Memory

Hindsight bank **`coding-agent::sessions`**, tagged `project:bazz-emu-inf`. Name the bank
explicitly on every retain — the harness binds one at launch and will not pick this one on its
own. Recall the same bank before nontrivial work, but weigh it against what you can see: this
repo's target host changed status abruptly and a confident stale fact about WaterDemon running
is exactly the failure mode to expect.

## Cross-repo

Read `/home/jt-admin/AGENTS.md` for routing and the standing cross-repo rules. The homelab
monitoring that consumed this box's `node_exporter` (`:9100`) and `nvidia_gpu_*` textfile
metrics lives in `~/homelab`, not here.
