#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Guarded fallback paths and compact emitter calls are intentional in these fixture-friendly collectors.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/prom.sh
source "${SCRIPT_DIR}/lib/prom.sh"

PROC_ROOT="${PROC_ROOT:-/proc}"
ROCM_SMI="${ROCM_SMI:-rocm-smi}"

prom_begin_scrape "nixl_amd_gpu_scrape_success" "Whether the AMD GPU exporter completed successfully."
if ! require_directory "$PROC_ROOT" "PROC_ROOT"; then
  exit 0
fi

emit_help "nixl_gpu_temperature_celsius" gauge "GPU temperature in Celsius."
emit_help "nixl_gpu_memory_used_bytes" gauge "GPU memory used in bytes."
emit_help "nixl_gpu_memory_total_bytes" gauge "GPU memory total in bytes."
emit_help "nixl_gpu_utilization_percent" gauge "GPU utilization percent."
emit_help "nixl_amd_gpu_rocm_smi_version" gauge "rocm-smi version detected."

if ! command_exists "$ROCM_SMI"; then
  emit_metric "nixl_amd_gpu_rocm_smi_version" 0 "version=unavailable"
  exit 0
fi

rocm_version="$("$ROCM_SMI" --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")"
emit_metric "nixl_amd_gpu_rocm_smi_version" 1 "version=${rocm_version}"

"$ROCM_SMI" --showallinfo --json 2>/dev/null | python3 -c '
import json
import sys

payload = json.load(sys.stdin)
for key, value in payload.items():
    index = "".join(ch for ch in key if ch.isdigit()) or "0"
    uuid = value.get("Unique ID") or value.get("Serial Number") or value.get("UUID") or f"amd-{index}"
    temp = value.get("Temperature (Sensor edge) (C)") or value.get("Temperature (Sensor junction) (C)") or value.get("Temperature (edge) (C)") or 0
    used = value.get("VRAM Total Used Memory (B)") or value.get("VRAM Used Memory (B)") or 0
    total = value.get("VRAM Total Memory (B)") or value.get("VRAM Total Available Memory (B)") or 0
    util = value.get("GPU use (%)") or value.get("GPU Use (%)") or 0
    print(index, uuid, temp, used, total, util, sep="\t")
' | while IFS=$'\t' read -r index uuid temp used total util; do
  is_number "$temp" && emit_metric "nixl_gpu_temperature_celsius" "$temp" "vendor=amd" "index=${index}" "uuid=${uuid}"
  is_integer "$used" && emit_metric "nixl_gpu_memory_used_bytes" "$used" "vendor=amd" "index=${index}" "uuid=${uuid}"
  is_integer "$total" && emit_metric "nixl_gpu_memory_total_bytes" "$total" "vendor=amd" "index=${index}" "uuid=${uuid}"
  is_number "$util" && emit_metric "nixl_gpu_utilization_percent" "$util" "vendor=amd" "index=${index}" "uuid=${uuid}"
done

prom_end_scrape "nixl_amd_gpu_scrape_success"
