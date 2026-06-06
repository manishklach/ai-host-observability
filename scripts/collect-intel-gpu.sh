#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/prom.sh
source "${SCRIPT_DIR}/lib/prom.sh"

PROC_ROOT="${PROC_ROOT:-/proc}"
INTEL_GPU_TOP="${INTEL_GPU_TOP:-intel_gpu_top}"

require_directory "$PROC_ROOT" "PROC_ROOT"

prom_begin_scrape "nixl_intel_gpu_scrape_success" "Whether the Intel GPU exporter completed successfully."
emit_help "nixl_gpu_utilization_percent" gauge "GPU utilization percent."

if ! command_exists "$INTEL_GPU_TOP"; then
  exit 0
fi

"$INTEL_GPU_TOP" -J -s 1 -n 1 2>/dev/null | python3 -c '
import json
import sys

def find_busy(obj):
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key == "busy" and isinstance(value, (int, float)):
                return value
            found = find_busy(value)
            if found is not None:
                return found
    elif isinstance(obj, list):
        for item in obj:
            found = find_busy(item)
            if found is not None:
                return found
    return None

payload = json.load(sys.stdin)
util = find_busy(payload)
if util is None:
    util = 0
print("0", "intel-0", util, sep="\t")
' | while IFS=$'\t' read -r index uuid util; do
  is_number "$util" && emit_metric "nixl_gpu_utilization_percent" "$util" "vendor=intel" "index=${index}" "uuid=${uuid}"
done

prom_end_scrape
