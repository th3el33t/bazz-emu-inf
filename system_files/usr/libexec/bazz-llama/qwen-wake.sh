#!/bin/bash
# llama-swap cmd for qwen3-coder-30b-a3b (Qwen3-Coder-30B-A3B-Instruct, MoE:
# 30B total / 3B active). Gate first: refuse to load ~17.7 GB while a stream,
# gamescope session or emulator owns the card (llama-swap surfaces the non-zero
# exit as a failed load, which the client sees as "unavailable").
#
# MoE decode reads only the ~3B active params per token, so this is far faster
# than the old dense 3.8-27B on the same 4090 — chosen for max token/s at good
# quality (UD-Q4_K_XL). No MTP draft (this model ships none) and no reasoning
# flags (it is a non-thinking Instruct coder).
#
# q4_0 KV with K == V: on CUDA flash-attention the fused kernel only accepts
# f16/q8_0/q4_0 AND requires K and V to match; mismatch silently drops to the
# unfused path (~9x slower decode). ctx 163840 fits alongside the weights in
# 24 GB (benched on-box: 22913 MiB at load, ~1.65 GB headroom; ~211 tok/s decode
# on code — vs the dense 3.8-27B's 49-83). q4_0 over q8_0 KV is deliberate: q8_0
# KV doubles the cache and would force ctx down to ~96k — for a coder, context
# length beats the small KV-precision gain. 256k q4_0 / 128k q8_0 both OOM.
#
# --parallel 2 (two 80k slots): partitioning the fixed 160k KV across slots is
# VRAM-free (total KV is set by --ctx-size, not --parallel), so this costs no extra
# memory. It serves the opencode/omo `hephaestus` execution lane, which fans out —
# two slots let a concurrent execution pair run without queueing on the one card at
# 211 tok/s. 80k/slot stays above the tool-definition context floor (a heavy tool
# fleet is serialized into the prompt before any work begins). Do NOT raise to 3-4
# without trimming the agent's tools; 53k/40k per slot risks overflow. Set back to 1
# only if a single task needs the full 160k (delegated slices are scoped, so rare).
#
# Sampling is Qwen's official recommendation for this model:
# temp 0.7, top-p 0.8, top-k 20, min-p 0.0, repeat-penalty 1.05.
set -euo pipefail

port=$1

if ! /usr/libexec/bazz-llama/gpu-busy.sh; then
    exit 1
fi

exec llama-server \
    --model /models/Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf \
    --alias qwen3-coder-30b-a3b \
    --host 0.0.0.0 --port "$port" \
    --gpu-layers 99 --flash-attn on \
    --cache-type-k q4_0 --cache-type-v q4_0 \
    --ctx-size 163840 --parallel 2 \
    --jinja \
    --load-mode mmap --threads 16 --metrics \
    --temp 0.7 --top-p 0.8 --top-k 20 --min-p 0.0 --repeat-penalty 1.05
