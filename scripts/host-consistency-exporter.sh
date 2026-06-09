#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Compact conditionals and fallback reads are intentional in exporter code.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/prom.sh
source "${SCRIPT_DIR}/lib/prom.sh"

PROC_ROOT="${PROC_ROOT:-/proc}"
NVIDIA_SMI="${NVIDIA_SMI:-nvidia-smi}"
MODINFO_CMD="${MODINFO_CMD:-modinfo}"
DMIDECODE_CMD="${DMIDECODE_CMD:-dmidecode}"
HOSTNAME_CMD="${HOSTNAME_CMD:-hostname}"
UNAME_CMD="${UNAME_CMD:-uname}"

emit_ulimit_metric() {
  local resource_name="$1"
  local type="$2"
  local mode_flag="$3"
  local value
  value="$(bash -lc "ulimit ${mode_flag}" 2>/dev/null || true)"
  case "${value}" in
  unlimited) value="-1" ;;
  esac
  is_integer "${value}" && emit_metric "nixl_host_ulimit" "${value}" "resource=${resource_name}" "type=${type}"
}

read_sysctl_value() {
  local name="$1"
  local path="${PROC_ROOT}/sys/${name//./\/}"
  local value
  value="$(safe_read_file "${path}" || true)"
  case "${name}" in
  net.ipv4.tcp_rmem | net.ipv4.tcp_wmem)
    awk '{ print $NF }' <<<"${value}"
    ;;
  *)
    printf '%s\n' "${value}"
    ;;
  esac
}

prom_begin_scrape "nixl_consistency_scrape_success" "Whether the host consistency exporter completed successfully."
if ! require_directory "${PROC_ROOT}" "PROC_ROOT"; then
  exit 0
fi

emit_help "nixl_host_kernel_version_info" gauge "Kernel version fingerprint for fleet consistency checks."
emit_help "nixl_host_driver_version_info" gauge "Driver version fingerprint for fleet consistency checks."
emit_help "nixl_host_cuda_version_info" gauge "CUDA version fingerprint from NVIDIA tooling."
emit_help "nixl_host_bios_version_info" gauge "BIOS vendor, version, and date fingerprint."
emit_help "nixl_host_cpu_microcode_info" gauge "CPU family, model, stepping, and microcode fingerprint."
emit_help "nixl_host_identity_info" gauge "Basic host identity labels."
emit_help "nixl_host_ulimit" gauge "Selected shell ulimit values."
emit_help "nixl_host_sysctl" gauge "Selected sysctl values important to AI host behavior."

kernel_version="$("${UNAME_CMD}" -r 2>/dev/null || true)"
major="$(sed -nE 's/^([0-9]+).*/\1/p' <<<"${kernel_version}")"
minor="$(sed -nE 's/^[0-9]+\.([0-9]+).*/\1/p' <<<"${kernel_version}")"
patch="$(sed -nE 's/^[0-9]+\.[0-9]+\.([0-9]+).*/\1/p' <<<"${kernel_version}")"
if [[ -n "${kernel_version}" ]]; then
  emit_metric "nixl_host_kernel_version_info" 1 "version=${kernel_version}" "major=${major:-0}" "minor=${minor:-0}" "patch=${patch:-0}"
fi

if command_exists "${MODINFO_CMD}"; then
  for driver in mlx5_core ib_core; do
    version="$("${MODINFO_CMD}" "${driver}" 2>/dev/null | awk -F: '/^version/ { gsub(/^[ \t]+/, "", $2); print $2; exit }' || true)"
    [[ -n "${version}" ]] && emit_metric "nixl_host_driver_version_info" 1 "driver=${driver%_core}" "version=${version}"
  done
fi

if command_exists "${NVIDIA_SMI}"; then
  driver_version="$("${NVIDIA_SMI}" --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 | xargs || true)"
  cuda_version="$("${NVIDIA_SMI}" --query-gpu=cuda_version --format=csv,noheader 2>/dev/null | head -n1 | xargs || true)"
  [[ -n "${driver_version}" ]] && emit_metric "nixl_host_driver_version_info" 1 "driver=nvidia" "version=${driver_version}"
  [[ -n "${cuda_version}" ]] && emit_metric "nixl_host_cuda_version_info" 1 "version=${cuda_version}"
fi

if command_exists "${DMIDECODE_CMD}"; then
  bios_vendor="$("${DMIDECODE_CMD}" -t bios 2>/dev/null | awk -F: '/Vendor:/ { gsub(/^[ \t]+/, "", $2); print $2; exit }')"
  bios_version="$("${DMIDECODE_CMD}" -t bios 2>/dev/null | awk -F: '/Version:/ { gsub(/^[ \t]+/, "", $2); print $2; exit }')"
  bios_date="$("${DMIDECODE_CMD}" -t bios 2>/dev/null | awk -F: '/Release Date:/ { gsub(/^[ \t]+/, "", $2); print $2; exit }')"
  if [[ -n "${bios_vendor}" || -n "${bios_version}" || -n "${bios_date}" ]]; then
    emit_metric "nixl_host_bios_version_info" 1 "vendor=${bios_vendor}" "version=${bios_version}" "date=${bios_date}"
  fi
fi

cpu_family="$(awk -F: '/cpu family/ { gsub(/^[ \t]+/, "", $2); print $2; exit }' "${PROC_ROOT}/cpuinfo" 2>/dev/null || true)"
cpu_model="$(awk -F: '$1 ~ /^model$/ { gsub(/^[ \t]+/, "", $2); print $2; exit }' "${PROC_ROOT}/cpuinfo" 2>/dev/null || true)"
cpu_stepping="$(awk -F: '/stepping/ { gsub(/^[ \t]+/, "", $2); print $2; exit }' "${PROC_ROOT}/cpuinfo" 2>/dev/null || true)"
cpu_microcode="$(awk -F: '/microcode/ { gsub(/^[ \t]+/, "", $2); print $2; exit }' "${PROC_ROOT}/cpuinfo" 2>/dev/null || true)"
if [[ -n "${cpu_family}" || -n "${cpu_model}" || -n "${cpu_stepping}" || -n "${cpu_microcode}" ]]; then
  emit_metric "nixl_host_cpu_microcode_info" 1 "family=${cpu_family}" "model=${cpu_model}" "stepping=${cpu_stepping}" "microcode=${cpu_microcode}"
fi

hostname_short="$("${HOSTNAME_CMD}" 2>/dev/null | head -n1 | xargs || true)"
hostname_fqdn="$("${HOSTNAME_CMD}" -f 2>/dev/null | head -n1 | xargs || true)"
arch="$("${UNAME_CMD}" -m 2>/dev/null | xargs || true)"
if [[ -n "${hostname_short}" || -n "${hostname_fqdn}" || -n "${arch}" ]]; then
  emit_metric "nixl_host_identity_info" 1 "hostname=${hostname_short}" "fqdn=${hostname_fqdn}" "arch=${arch}"
fi

emit_ulimit_metric "nofile" "soft" "-Sn"
emit_ulimit_metric "nofile" "hard" "-Hn"
emit_ulimit_metric "nproc" "soft" "-Su"
emit_ulimit_metric "nproc" "hard" "-Hu"
emit_ulimit_metric "memlock" "soft" "-Sl"
emit_ulimit_metric "memlock" "hard" "-Hl"
emit_ulimit_metric "stack" "soft" "-Ss"
emit_ulimit_metric "stack" "hard" "-Hs"
emit_ulimit_metric "core" "soft" "-Sc"
emit_ulimit_metric "core" "hard" "-Hc"

sysctls=(
  net.core.rmem_max
  net.core.wmem_max
  net.core.netdev_max_backlog
  net.ipv4.tcp_rmem
  net.ipv4.tcp_wmem
  kernel.numa_balancing
  vm.zone_reclaim_mode
  net.ipv4.tcp_slow_start_after_idle
  net.core.somaxconn
  net.ipv4.tcp_max_syn_backlog
  kernel.perf_event_paranoid
  vm.nr_hugepages
  vm.nr_overcommit_hugepages
)
for sysctl_name in "${sysctls[@]}"; do
  value="$(read_sysctl_value "${sysctl_name}")"
  is_integer "${value}" && emit_metric "nixl_host_sysctl" "${value}" "name=${sysctl_name}"
done

prom_end_scrape "nixl_consistency_scrape_success"
