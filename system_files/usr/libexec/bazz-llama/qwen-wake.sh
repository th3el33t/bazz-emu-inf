#!/bin/bash
# llama-swap cmd for qwen3.8-27b. Gate first: refuse to load ~17 GB while a
# stream, gamescope session or emulator owns the card (llama-swap surfaces the
# non-zero exit as a failed load, which the client sees as "unavailable").
#
# Flags are the shipped Windows config (49-83 tok/s, benched 2026-08-28):
# Q4_K_XL @ 120k ctx, q4_0 KV — K and V MUST match on CUDA flash-attention or
# llama.cpp silently drops to the unfused path (~9x slower decode). MTP is a
# separate draft model since the newer llama.cpp builds split it out.
set -euo pipefail

port=$1

if ! /usr/libexec/bazz-llama/gpu-busy.sh; then
    exit 1
fi

exec llama-server \
    --model /models/Qwen3.8-27B-UD-Q4_K_XL.gguf \
    --model-draft /models/mtp-Qwen3.8-27B-Q4_0.gguf \
    --spec-type draft-mtp,ngram-mod --spec-draft-n-max 12 \
    --alias qwen3.8-27b \
    --host 0.0.0.0 --port "$port" \
    --gpu-layers 99 --flash-attn on \
    --cache-type-k q4_0 --cache-type-v q4_0 \
    --ctx-size 122880 --parallel 1 \
    --jinja --reasoning on --reasoning-effort low \
    --no-mmap --threads 16 --metrics \
    --temp 0.7 --top-p 0.8 --repeat-penalty 1.0
