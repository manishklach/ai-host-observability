#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Compact fallback reads are intentional in exporter code.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/prom.sh
source "${SCRIPT_DIR}/lib/prom.sh"

PROC_ROOT="${PROC_ROOT:-/proc}"

prom_begin_scrape "nixl_watchdog_scrape_success" "Whether the watchdog exporter completed successfully."
if ! require_directory "${PROC_ROOT}" "PROC_ROOT"; then
  exit 0
fi

emit_help "nixl_kernel_watchdog_enabled" gauge "Whether the kernel watchdog is enabled."
emit_help "nixl_kernel_watchdog_thresh_seconds" gauge "Kernel watchdog threshold in seconds."
emit_help "nixl_kernel_hung_task_timeout_seconds" gauge "Kernel hung task timeout in seconds."
emit_help "nixl_kernel_nmi_watchdog_enabled" gauge "Whether the NMI watchdog is enabled."
emit_help "nixl_kernel_softlockup_panic" gauge "Whether the kernel panics on soft lockups."
emit_help "nixl_kernel_panic_timeout_seconds" gauge "Kernel panic reboot timeout in seconds."

emitted=0
read_sysctl_metric() {
  local relative_path="$1"
  local metric_name="$2"
  local value
  value="$(safe_read_file "${PROC_ROOT}/sys/${relative_path}" || true)"
  if is_integer "${value}"; then
    emit_metric "${metric_name}" "${value}"
    emitted=1
  fi
}

read_sysctl_metric "kernel/watchdog" "nixl_kernel_watchdog_enabled"
read_sysctl_metric "kernel/watchdog_thresh" "nixl_kernel_watchdog_thresh_seconds"
read_sysctl_metric "kernel/hung_task_timeout_secs" "nixl_kernel_hung_task_timeout_seconds"
read_sysctl_metric "kernel/nmi_watchdog" "nixl_kernel_nmi_watchdog_enabled"
read_sysctl_metric "kernel/softlockup_panic" "nixl_kernel_softlockup_panic"
read_sysctl_metric "kernel/panic" "nixl_kernel_panic_timeout_seconds"

if [[ "${emitted}" -eq 1 ]]; then
  prom_end_scrape "nixl_watchdog_scrape_success"
fi
