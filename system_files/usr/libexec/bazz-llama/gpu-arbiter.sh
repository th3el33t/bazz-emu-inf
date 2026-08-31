#!/bin/bash
# gpu-arbiter.sh — evict resident inference the moment a HUMAN claims the 4090.
#
# The wake gate (qwen-wake.sh -> gpu-busy.sh) only refuses to LOAD Qwen while a
# stream/gamescope/emulator owns the card. It does nothing about a model that is
# ALREADY resident (~23.7 GB) when a game launches: llama-swap would hold it for
# the full 15-min ttl, starving the game of VRAM. This is the Linux replacement
# for the Windows VRAM-Reclaim script.
#
# Design: poll gpu-busy.sh (the ONE busy predicate — do not re-derive it here)
# every POLL_SECS; on a free->busy edge, if llama-swap has a model loaded, hit
# its /unload endpoint so the card is freed within POLL_SECS of the game
# appearing. WhisperX already self-defers per file, so only Qwen needs eviction.
#
# ponytail: 3s poll, uniform across all launcher types. Worst case is ~3s of VRAM
# contention at game-launch (well under a game's own shader/init load). If that
# window ever bites, add a per-launcher event hook (Sunshine prep-cmd / ES-DE
# pre-launch script) that calls /unload directly — but only then.
set -uo pipefail

POLL_SECS="${POLL_SECS:-3}"
SWAP_URL="${SWAP_URL:-http://127.0.0.1:8085}"

was_busy=0

while true; do
    if reason=$(/usr/libexec/bazz-llama/gpu-busy.sh); then
        # free
        was_busy=0
    else
        # busy (reason on stdout). Only act on the edge and only if a model is up.
        if [ "$was_busy" -eq 0 ]; then
            running=$(curl -fsS --max-time 5 "$SWAP_URL/running" 2>/dev/null || echo '{"running":[]}')
            if [[ "$running" != *'"running":[]'* ]]; then
                echo "arbiter: $reason -> evicting resident model (/unload)"
                curl -fsS --max-time 10 "$SWAP_URL/unload" >/dev/null 2>&1 \
                    && echo "arbiter: unload requested" \
                    || echo "arbiter: unload call failed (llama-swap down?)" >&2
            fi
            was_busy=1
        fi
    fi
    sleep "$POLL_SECS"
done
