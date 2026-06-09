#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Brace-style and set -e informational warnings are intentionally relaxed here for readability and guarded fallback paths.

SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
LIB_DIR="${LIB_DIR:-${SCRIPT_DIR}/lib}"
# shellcheck source=scripts/lib/prom.sh
source "${LIB_DIR}/prom.sh"

# Wrapper-level toggles let operators trade simplicity for concurrency and structured logs.
OUT_DIR="${OUT_DIR:-/var/lib/node_exporter/textfile_collector}"
EXPORTERS="${EXPORTERS:-}"
PARALLEL="${PARALLEL:-0}"
MAX_PARALLEL="${MAX_PARALLEL:-0}"
LOG_FORMAT="${LOG_FORMAT:-text}"

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
  "nixl_mce"
  "nixl_thermal"
  "nixl_nvlink"
  "nixl_watchdog"
  "nixl_timesync"
  "nixl_job"
  "nixl_netflow"
  "nixl_gpumem"
  "nixl_baseline"
  "nixl_collector"
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
  ["nixl_mce"]="mce-ras-exporter.sh"
  ["nixl_thermal"]="cpu-thermal-exporter.sh"
  ["nixl_nvlink"]="nvlink-exporter.sh"
  ["nixl_watchdog"]="watchdog-exporter.sh"
  ["nixl_timesync"]="timesync-exporter.sh"
  ["nixl_job"]="job-heartbeat-exporter.sh"
  ["nixl_netflow"]="net-flow-exporter.sh"
  ["nixl_gpumem"]="gpu-mem-pressure-exporter.sh"
  ["nixl_baseline"]="anomaly-baseline-exporter.sh"
  ["nixl_collector"]="collector-health-exporter.sh"
)

cleanup() {
  if ((${#TMP_FILES[@]} > 0)); then
    rm -f -- "${TMP_FILES[@]}"
  fi
}
trap cleanup EXIT

json_escape() {
  local str="$1"
  str="${str//\\/\\\\}"
  str="${str//\"/\\\"}"
  str="${str//$'\n'/\\n}"
  str="${str//$'\r'/\\r}"
  str="${str//$'\t'/\\t}"
  printf '%s' "$str"
}

log_info() {
  local msg="$1"
  local timestamp
  timestamp="$(date -Iseconds)"
  if [[ "$LOG_FORMAT" == "json" ]]; then
    if command_exists jq; then
      printf '{"level":"info","timestamp":"%s","message":%s}\n' "$timestamp" "$(jq -n --arg m "$msg" '$m')"
    else
      printf '{"level":"info","timestamp":"%s","message":"%s"}\n' "$timestamp" "$(json_escape "$msg")"
    fi
  else
    printf '[%s] INFO %s\n' "$timestamp" "$msg"
  fi
}

log_error() {
  local msg="$1"
  local timestamp
  timestamp="$(date -Iseconds)"
  if [[ "$LOG_FORMAT" == "json" ]]; then
    if command_exists jq; then
      printf '{"level":"error","timestamp":"%s","message":%s}\n' "$timestamp" "$(jq -n --arg m "$msg" '$m')"
    else
      printf '{"level":"error","timestamp":"%s","message":"%s"}\n' "$timestamp" "$(json_escape "$msg")"
    fi
  else
    printf '[%s] ERROR %s\n' "$timestamp" "$msg" >&2
  fi
}

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
  local start_ns end_ns duration_s

  final_file="${OUT_DIR}/${exporter}.prom"
  new_tmp_file
  body_file="$NEW_TMP_FILE"
  new_tmp_file
  stderr_file="$NEW_TMP_FILE"

  if [[ ! -x "$script_path" && ! -f "$script_path" ]]; then
    write_failure_file "$exporter" "missing exporter script: ${script_name}" "$final_file"
    return 0
  fi

  start_ns="$(date +%s%N)"
  if bash "$script_path" >"$body_file" 2>"$stderr_file"; then
    end_ns="$(date +%s%N)"
    duration_s="$(awk -v ns=$((end_ns - start_ns)) 'BEGIN {printf "%.6f", ns/1e9}')"
    local with_duration_file="${body_file}.with_duration"
    {
      cat -- "$body_file"
      prom_set_timestamp ""
      emit_help "ai_host_exporter_duration_seconds" gauge "Exporter execution duration in seconds."
      emit_metric "ai_host_exporter_duration_seconds" "$duration_s" "exporter=${exporter}"
    } >"$with_duration_file"
    write_success_file "$exporter" "$with_duration_file" "$final_file"
    rm -f -- "$with_duration_file"
    log_info "exporter completed: ${exporter} (${duration_s}s)"
    return 0
  fi

  end_ns="$(date +%s%N)"
  duration_s="$(awk -v ns=$((end_ns - start_ns)) 'BEGIN {printf "%.6f", ns/1e9}')"
  error_message="$(tr '\r' ' ' <"$stderr_file" | head -n 1)"
  if [[ -z "$error_message" ]]; then
    error_message="exporter exited non-zero"
  fi
  local with_duration_file="${body_file}.with_duration"
  {
    prom_set_timestamp ""
    emit_wrapper_header
    emit_help "ai_host_exporter_duration_seconds" gauge "Exporter execution duration in seconds."
    emit_metric "ai_host_exporter_duration_seconds" "$duration_s" "exporter=${exporter}"
    emit_metric "ai_host_exporter_last_run_success" 0 "exporter=${exporter}"
    emit_metric "ai_host_exporter_last_run_error" 1 "exporter=${exporter}" "error=${error_message}"
  } >"$with_duration_file"
  mv -f -- "$with_duration_file" "$final_file"
  log_error "exporter failed: ${exporter}: ${error_message}"
}

select_exporters() {
  if [[ -n "$EXPORTERS" ]]; then
    read -r -a SELECTED_EXPORTERS <<<"$EXPORTERS"
  else
    SELECTED_EXPORTERS=("${DEFAULT_EXPORTERS[@]}")
  fi
}

run_exporters_parallel() {
  local -a pids=()
  local max_parallel="${MAX_PARALLEL}"
  if [[ "$max_parallel" -le 0 ]]; then
    max_parallel="${#SELECTED_EXPORTERS[@]}"
  fi

  for exporter in "${SELECTED_EXPORTERS[@]}"; do
    if [[ -z "${EXPORTER_SCRIPTS[$exporter]:-}" ]]; then
      write_failure_file "$exporter" "unknown exporter" "${OUT_DIR}/${exporter}.prom"
      continue
    fi

    while ((${#pids[@]} >= max_parallel)); do
      wait -n
      pids=("${pids[@]##*[!0-9]*}")
    done

    run_exporter "$exporter" &
    pids+=("$!")
  done

  for pid in "${pids[@]}"; do
    wait "$pid"
  done
}

mkdir -p -- "$OUT_DIR"
select_exporters

log_info "starting collection run with ${#SELECTED_EXPORTERS[@]} exporters (parallel=${PARALLEL})"

if [[ "$PARALLEL" == "1" ]]; then
  run_exporters_parallel
else
  for exporter in "${SELECTED_EXPORTERS[@]}"; do
    if [[ -z "${EXPORTER_SCRIPTS[$exporter]:-}" ]]; then
      write_failure_file "$exporter" "unknown exporter" "${OUT_DIR}/${exporter}.prom"
      continue
    fi
    run_exporter "$exporter"
  done
fi
