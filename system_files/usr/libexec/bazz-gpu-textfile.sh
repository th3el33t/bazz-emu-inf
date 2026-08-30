#!/bin/bash
# Emits nvidia_gpu_* metrics into node_exporter's textfile directory, replacing
# the Windows nvidia-smi textfile collector that fed the WaterDemonGpuHot alert.
# Metric names deliberately match the old Windows collector so the alert rules
# in the homelab monitoring stack keep working unchanged. Non-numeric fields
# (e.g. fan.speed reporting "[N/A]") are skipped — a malformed line would make
# node_exporter reject the whole scrape.
set -euo pipefail

outdir=/var/lib/node_exporter/textfile
mkdir -p "$outdir"
tmp="$outdir/.gpu.prom.tmp"

nvidia-smi --query-gpu=temperature.gpu,fan.speed,power.draw,utilization.gpu,clocks.sm,memory.used,memory.total \
           --format=csv,noheader,nounits | awk -F', ' '{
  if ($1 ~ /^[0-9.]+$/) printf "nvidia_gpu_temperature_celsius %s\n", $1
  if ($2 ~ /^[0-9.]+$/) printf "nvidia_gpu_fan_speed_percent %s\n", $2
  if ($3 ~ /^[0-9.]+$/) printf "nvidia_gpu_power_draw_watts %s\n", $3
  if ($4 ~ /^[0-9.]+$/) printf "nvidia_gpu_utilization_percent %s\n", $4
  if ($5 ~ /^[0-9.]+$/) printf "nvidia_gpu_clock_sm_mhz %s\n", $5
  if ($6 ~ /^[0-9.]+$/) printf "nvidia_gpu_memory_used_bytes %s\n", $6 * 1024 * 1024
  if ($7 ~ /^[0-9.]+$/) printf "nvidia_gpu_memory_total_bytes %s\n", $7 * 1024 * 1024
}' > "$tmp"

mv "$tmp" "$outdir/gpu.prom"
