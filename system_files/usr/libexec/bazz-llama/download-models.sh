#!/bin/bash
# First-boot downloader for the Qwen GGUF weights (two-layer rule: weights are
# the DATA layer, never the image).
#
# Uses huggingface_hub's Xet backend (hf_xet) for fast transfers — measured
# ~40x over plain curl on this estate (HF_XET_HIGH_PERFORMANCE=1). huggingface_hub
# verifies integrity itself, so no manual sha256 loop. An optional HF_TOKEN
# (dropped by the owner in /etc/bazz-emu-inf/hf.env, loaded by the service unit)
# lifts anonymous rate limits; without it the download still works, just slower.
#
# Invoked as `python3 -c` rather than the `hf` CLI on purpose: the library is
# installed system-wide in /usr, so /usr/bin/python3 has a normal exec context
# for systemd. (A user-installed hf script under /root/.local/bin is blocked by
# SELinux when systemd tries to exec it.) Idempotent via stamp; huggingface_hub
# also skips any file already present and valid.
set -euo pipefail

stamp=/var/lib/bazz-emu-inf/llama-models-installed
dir=/var/lib/llama-models
repo=unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF
files=("Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf")

[ -f "$stamp" ] && exit 0
mkdir -p "$(dirname "$stamp")" "$dir"

export HF_XET_HIGH_PERFORMANCE="${HF_XET_HIGH_PERFORMANCE:-1}"

for f in "${files[@]}"; do
    echo "downloading $f"
    /usr/bin/python3 - "$repo" "$f" "$dir" <<'PY'
import sys
from huggingface_hub import hf_hub_download
repo, fname, dest = sys.argv[1:4]
hf_hub_download(repo, fname, local_dir=dest)
PY
done

touch "$stamp"
