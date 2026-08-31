#!/bin/bash
# Transcribe every file dropped into /srv/audio/in (via the Samba [audio]
# share), writing .srt/.vtt/.json/... to /srv/audio/out and moving originals to
# /srv/audio/done. Triggered by bazz-whisperx.path (DirectoryNotEmpty) and
# retried by bazz-whisperx.timer — a GPU-busy defer is safe: the files stay in
# in/ and the next trigger picks them up. One-shot container per file (the
# jim60105 image is CLI-only); the ~15 s model load per file is fine next to
# multi-minute transcription jobs.
set -uo pipefail

shopt -s nullglob
for f in /srv/audio/in/*; do
    [ -f "$f" ] || continue
    if ! /usr/libexec/bazz-llama/gpu-busy.sh; then
        echo "GPU busy, deferring: $(basename "$f")"
        continue
    fi
    base=$(basename "$f")
    echo "transcribing: $base"
    if podman run --rm --device nvidia.com/gpu=all \
        -v /srv/audio:/srv/audio:Z \
        ghcr.io/jim60105/whisperx:large-v3-en \
        --output_dir /srv/audio/out --output_format all \
        --compute_type float16 --batch_size 8 \
        "/srv/audio/in/$base"; then
        mv "$f" /srv/audio/done/
    else
        echo "transcription FAILED, leaving in place: $base" >&2
    fi
done
