#!/bin/sh
# llama-swap container liveness — deeper than the bare proxy /health.
#
#   Layer 1: /health must answer            -> catches a dead llama-swap proxy.
#   Layer 2: if a model is loaded and READY, it must complete a real 1-token
#            generation                      -> catches a model WEDGED by a GPU
#            fault (ErrorDeviceLost): llama-swap keeps 200ing on /health while
#            every real request fails. /health alone is that false-healthy gap.
#
# Idle-safe: nothing loaded (box idle, or the GPU arbiter evicted the model for a
# game / Moonlight stream) -> no probe, no forced load, so this never fights the
# arbiter or wakes the GPU on its own.
#
# Ceilings (ponytail): waterdemon serves completion/chat models only, so a
# /v1/completions probe is valid for every model it runs, and it runs one
# on-demand model at a time -> the "first ready model" heuristic is exact here.
# Add a matching probe (/v1/embeddings, /v1/rerank) if an embed/rerank model is
# ever served on this box. The coder is --parallel 2, so this probe gets its own
# slot; podman's 3-retry default absorbs a one-off queue under full saturation.
set -e
BASE=http://localhost:8085

curl -sf --max-time 5 "$BASE/health" >/dev/null || exit 1

r=$(curl -sf --max-time 5 "$BASE/running") || exit 1
echo "$r" | grep -q '"state":"ready"' || exit 0        # nothing ready -> idle, healthy

m=$(echo "$r" | grep -o '"model":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -z "$m" ] && exit 0

curl -sf --max-time 20 "$BASE/v1/completions" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$m\",\"prompt\":\"ping\",\"max_tokens\":1,\"temperature\":0}" \
  >/dev/null || exit 1

exit 0
