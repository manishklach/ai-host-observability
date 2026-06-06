#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
LIB_DIR="${LIB_DIR:-${SCRIPT_DIR}/lib}"
# shellcheck source=scripts/lib/prom.sh
source "${LIB_DIR}/prom.sh"

OUT_DIR="${OUT_DIR:-/var/lib/node_exporter/textfile_collector}"
EXPORTERS="${EXPORTERS:-}"

declare -a TMP_FILES=()
declare -a DEFAULT_EXPORTERS=(
  "nixl_host_mem"
  "nixl_rdma_link"
  "nixl_cpu_irq"
  "nixl_numa"
  "nixl_kernel_log"
  "nixl_gpu"
  "nixl_amd_gpu"
  "nixl_intel_gpu"
  "nixl_disk"
  "nixl_network_stack"
  "nixl_process_memory"
  "nixl_pcie_vfio"
)

declare -A EXPORTER_SCRIPTS=(
  ["nixl_host_mem"]="nixl-host-mem-exporter.sh"
  ["nixl_rdma_link"]="rdma-link-exporter.sh"
  ["nixl_cpu_irq"]="cpu-irq-exporter.sh"
  ["nixl_numa"]="numa-exporter.sh"
  ["nixl_kernel_log"]="kernel-log-scan-exporter.sh"
  ["nixl_gpu"]="gpu-exporter.sh"
  ["nixl_amd_gpu"]="collect-amd-gpu.sh"
  ["nixl_intel_gpu"]="collect-intel-gpu.sh"
  ["nixl_disk"]="disk-filesystem-exporter.sh"
  ["nixl_network_stack"]="network-stack-exporter.sh"
  ["nixl_process_memory"]="process-memory-exporter.sh"
  ["nixl_pcie_vfio"]="pcie-vfio-exporter.sh"
)

cleanup() {
  if ((${#TMP_FILES[@]} > 0)); then
    rm -f -- "${TMP_FILES[@]}"
  fi
}
trap cleanup EXIT

new_tmp_file() {
  NEW_TMP_FILE="$(mktemp "${OUT_DIR}/.ai-host-observability.XXXXXX")"
  TMP_FILES+=("$NEW_TMP_FILE")
}

emit_wrapper_header() {
  emit_help "ai_host_exporter_last_run_success" gauge "Whether the wrapper completed the exporter successfully."
  emit_help "ai_host_exporter_last_run_error" gauge "Wrapper-level exporter error marker."
}

write_success_file() {
  local exporter="$1"
  local source_file="$2"
  local target_file="$3"
  local tmp_file
  new_tmp_file
  tmp_file="$NEW_TMP_FILE"

  {
    cat -- "$source_file"
    prom_set_timestamp ""
    emit_wrapper_header
    emit_metric "ai_host_exporter_last_run_success" 1 "exporter=${exporter}"
  } >"$tmp_file"

  mv -f -- "$tmp_file" "$target_file"
}

write_failure_file() {
  local exporter="$1"
  local error_message="$2"
  local target_file="$3"
  local tmp_file
  new_tmp_file
  tmp_file="$NEW_TMP_FILE"

  prom_set_timestamp ""
  {
    emit_wrapper_header
    emit_metric "ai_host_exporter_last_run_success" 0 "exporter=${exporter}"
    emit_metric "ai_host_exporter_last_run_error" 1 "exporter=${exporter}" "error=${error_message}"
  } >"$tmp_file"

  mv -f -- "$tmp_file" "$target_file"
}

run_exporter() {
  local exporter="$1"
  local script_name="${EXPORTER_SCRIPTS[$exporter]}"
  local script_path="${SCRIPT_DIR}/${script_name}"
  local body_file stderr_file final_file error_message

  final_file="${OUT_DIR}/${exporter}.prom"
  new_tmp_file
  body_file="$NEW_TMP_FILE"
  new_tmp_file
  stderr_file="$NEW_TMP_FILE"

  if [[ ! -x "$script_path" && ! -f "$script_path" ]]; then
    write_failure_file "$exporter" "missing exporter script: ${script_name}" "$final_file"
    return 0
  fi

  if bash "$script_path" >"$body_file" 2>"$stderr_file"; then
    write_success_file "$exporter" "$body_file" "$final_file"
    return 0
  fi

  error_message="$(tr '\r' ' ' <"$stderr_file" | head -n 1)"
  if [[ -z "$error_message" ]]; then
    error_message="exporter exited non-zero"
  fi
  write_failure_file "$exporter" "$error_message" "$final_file"
  printf 'exporter failed: %s: %s\n' "$exporter" "$error_message" >&2
}

select_exporters() {
  if [[ -n "$EXPORTERS" ]]; then
    read -r -a SELECTED_EXPORTERS <<<"$EXPORTERS"
  else
    SELECTED_EXPORTERS=("${DEFAULT_EXPORTERS[@]}")
  fi
}

mkdir -p -- "$OUT_DIR"
select_exporters

for exporter in "${SELECTED_EXPORTERS[@]}"; do
  if [[ -z "${EXPORTER_SCRIPTS[$exporter]:-}" ]]; then
    write_failure_file "$exporter" "unknown exporter" "${OUT_DIR}/${exporter}.prom"
    continue
  fi
  run_exporter "$exporter"
done
