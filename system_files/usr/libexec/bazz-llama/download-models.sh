#!/bin/bash
# First-boot downloader for the Qwen GGUF weights (two-layer rule: weights are
# the DATA layer, never the image). Verifies each file against the sha256 that
# the HuggingFace API reports for it. Idempotent via stamp; safe to re-run —
# completed files are skipped by checksum.
set -euo pipefail

stamp=/var/lib/bazz-emu-inf/llama-models-installed
dir=/var/lib/llama-models
repo=unsloth/Qwen3.8-27B-GGUF
files=("Qwen3.8-27B-UD-Q4_K_XL.gguf" "MTP/mtp-Qwen3.8-27B-Q4_0.gguf")

[ -f "$stamp" ] && exit 0
mkdir -p "$(dirname "$stamp")" "$dir/MTP"

# File name -> lfs sha256, straight from the HF API.
declare -A sums
while IFS=$'\t' read -r name sha; do
    sums[$name]=$sha
done < <(curl -fsSL "https://huggingface.co/api/models/$repo?blobs=true" | python3 -c '
import json, sys
for f in json.load(sys.stdin)["siblings"]:
    lfs = f.get("lfs") or {}
    if f["rfilename"].endswith(".gguf") and lfs.get("sha256"):
        print(f["rfilename"], lfs["sha256"], sep="\t")
')

for f in "${files[@]}"; do
    dest="$dir/$(basename "$f")"
    want="${sums[$f]:-}"
    [ -n "$want" ] || { echo "no sha256 from HF for $f" >&2; exit 1; }
    if [ -f "$dest" ] && [ "$(sha256sum "$dest" | cut -d' ' -f1)" = "$want" ]; then
        echo "$dest already present and valid"
        continue
    fi
    echo "downloading $f"
    curl -fSL --retry 5 --retry-all-errors -C - \
        -o "$dest.partial" "https://huggingface.co/$repo/resolve/main/$f"
    got=$(sha256sum "$dest.partial" | cut -d' ' -f1)
    [ "$got" = "$want" ] || { echo "sha256 mismatch on $f: got $got want $want" >&2; rm -f "$dest.partial"; exit 1; }
    mv "$dest.partial" "$dest"
done

touch "$stamp"
