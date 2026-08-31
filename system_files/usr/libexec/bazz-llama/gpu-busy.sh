#!/bin/bash
# gpu-busy.sh — water-demon: is the 4090 claimed by a HUMAN workload right now?
#
#   exit 0 = free (stdout empty)
#   exit 1 = busy (stdout = one-line reason)
#
# Linux port of the Windows gpu-busy.ps1, keeping its contract. THE single
# predicate: qwen-wake.sh (llama-swap wake gate) consults it today and the
# GPU-arbitration layer will reuse it — written N times, the copies would stay
# plausible while diverging. Runs inside the llama-swap container, which is
# --pid=host + host network, so host processes and connections are visible.
#
# Note on the Windows Steam signal: the original read RunningAppID from HKCU.
# Linux Steam has no equivalent registry signal, but every game here launches
# inside gamescope (per-stream gamescope design), so gamescope IS the Steam
# signal. Wallpaper Engine (the exclusion that motivated HKCU precision on
# Windows) does not exist on this box.
set -uo pipefail

reason=""

# 1. A live Moonlight/Sunshine stream (Sunshine's TCP ports).
streams=$(ss -tn state established '( sport = :47984 or sport = :47989 or sport = :48010 )' 2>/dev/null | tail -n +2 | wc -l)
if [ "$streams" -gt 0 ]; then
    reason="moonlight stream live ($streams connection(s))"
fi

# 2. A gamescope session — every Steam game and per-stream game runs in one.
if [ -z "$reason" ] && pgrep -x gamescope >/dev/null 2>&1; then
    reason="a gamescope session is running"
fi

# 3. Non-Steam emulation launched straight from the desktop/ES-DE.
#    Flatpaks keep their binary comm (retroarch, pcsx2-qt); the AppImages run
#    via AppRun, so they match on the cmdline path instead.
if [ -z "$reason" ]; then
    for pat in retroarch pcsx2-qt ES-DE.AppImage DuckStation.AppImage; do
        if pgrep -f "$pat" >/dev/null 2>&1; then
            reason="'$pat' is running"
            break
        fi
    done
fi

if [ -n "$reason" ]; then
    echo "$reason"
    exit 1
fi
exit 0
