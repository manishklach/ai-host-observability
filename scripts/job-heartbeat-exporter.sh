#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Compact conditionals and fallback reads are intentional in exporter code.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/prom.sh
source "${SCRIPT_DIR}/lib/prom.sh"

OUT_DIR="${OUT_DIR:-/var/lib/node_exporter/textfile_collector}"
STATE_DIR="${STATE_DIR:-${OUT_DIR}/.heartbeat}"
PS_CMD="${PS_CMD:-ps}"
FIND_CMD="${FIND_CMD:-find}"
TAIL_CMD="${TAIL_CMD:-tail}"
STAT_CMD="${STAT_CMD:-stat}"
NOW_EPOCH="${NOW_EPOCH:-$(date +%s)}"
CHECKPOINT_WINDOW_SECONDS="${CHECKPOINT_WINDOW_SECONDS:-1800}"
STALL_THRESHOLD_SECONDS="${STALL_THRESHOLD_SECONDS:-600}"
CHECKPOINT_DIRS="${CHECKPOINT_DIRS:-/tmp /scratch /checkpoint /mnt/checkpoints /data}"
LOG_DIRS="${LOG_DIRS:-/tmp /var/log /scratch /home}"

safe_age_seconds() {
  local path="$1"
  local mtime
  mtime="$("${STAT_CMD}" -c '%Y' "${path}" 2>/dev/null || true)"
  if is_integer "${mtime}"; then
    awk -v now="${NOW_EPOCH}" -v mtime="${mtime}" 'BEGIN {
      age = now - mtime
      if (age < 0) {
        age = 0
      }
      printf "%.0f\n", age
    }'
  else
    printf '0\n'
  fi
}

recent_gpu_activity() {
  if [[ ! -d "${OUT_DIR}" ]]; then
    printf '0\n'
    return 0
  fi

  awk '
    index($0, "#") == 1 { next }
    $1 !~ /^nixl_gpu_utilization_percent([{| ]|$)/ { next }
    $2 + 0 > 10 { active = 1 }
    END { print active ? 1 : 0 }
  ' "${OUT_DIR}"/*.prom 2>/dev/null || printf '0\n'
}

summarize_cmdline() {
  local raw="$1"
  raw="$(xargs <<<"${raw}")"
  if ((${#raw} > 96)); then
    printf '%s\n' "${raw:0:96}"
  else
    printf '%s\n' "${raw}"
  fi
}

extract_last_step() {
  local path="$1"
  "${TAIL_CMD}" -n 100 "${path}" 2>/dev/null | awk '
    {
      for (i = 1; i <= NF; i++) {
        token = $i
        gsub(/[^0-9\/]/, "", token)
        if (token ~ /^[0-9]+\/[0-9]+$/) {
          split(token, parts, "/")
          last = parts[1]
        } else if (tolower($i) ~ /^(step|iter|epoch)$/ && (i + 1) <= NF) {
          candidate = $(i + 1)
          gsub(/[^0-9]/, "", candidate)
          if (candidate != "") {
            last = candidate
          }
        } else if (tolower($i) ~ /^(step|iter|epoch)[=:]?[0-9]+$/) {
          candidate = $i
          gsub(/[^0-9]/, "", candidate)
          if (candidate != "") {
            last = candidate
          }
        }
      }
    }
    END { print last + 0 }
  '
}

write_state() {
  local pid="$1"
  local step="$2"
  local updated="${3:-${NOW_EPOCH}}"
  mkdir -p "${STATE_DIR}"
  printf 'step=%s\nupdated=%s\n' "${step}" "${updated}" >"${STATE_DIR}/${pid}.state"
}

read_state_step() {
  local pid="$1"
  local state_file="${STATE_DIR}/${pid}.state"
  if [[ -r "${state_file}" ]]; then
    awk -F= '$1 == "step" { print $2 }' "${state_file}"
  else
    printf '0\n'
  fi
}

read_state_progress_updated() {
  local pid="$1"
  local state_file="${STATE_DIR}/${pid}.state"
  if [[ -r "${state_file}" ]]; then
    awk -F= '$1 == "updated" { print $2 }' "${state_file}"
  else
    printf '0\n'
  fi
}

log_state_key() {
  local path="$1"
  printf '%s\n' "${path//[^[:alnum:]]/_}"
}

prom_begin_scrape "nixl_job_scrape_success" "Whether the training job heartbeat exporter completed successfully."
if ! command_exists "${PS_CMD}"; then
  exit 0
fi

emit_help "nixl_job_training_processes_total" gauge "Count of active training-like processes detected on the host."
emit_help "nixl_job_process_uptime_seconds" gauge "Uptime in seconds for detected training-like processes."
emit_help "nixl_job_process_cpu_percent" gauge "CPU percent for detected training-like processes."
emit_help "nixl_job_process_mem_rss_bytes" gauge "RSS bytes for detected training-like processes."
emit_help "nixl_job_checkpoint_files_recent" gauge "Recent checkpoint file count per configured root."
emit_help "nixl_job_checkpoint_last_write_age_seconds" gauge "Age in seconds of the newest checkpoint beneath the configured root."
emit_help "nixl_job_log_last_step" gauge "Last detected step-like progress marker for a log file."
emit_help "nixl_job_log_last_update_age_seconds" gauge "Age in seconds of the latest modification for a log file."
emit_help "nixl_job_stall_suspected" gauge "Whether the host appears to be running active GPUs without checkpoint or log progress."
emit_help "nixl_job_stall_duration_seconds" gauge "Duration in seconds for the current suspected training stall."

training_processes=0
while read -r pid etimes cpu rss cmdline; do
  [[ -n "${pid}" ]] || continue
  case "${cmdline}" in
  *python* | *torchrun* | *deepspeed* | *accelerate* | *mpirun* | *srun*)
    summary="$(summarize_cmdline "${cmdline}")"
    training_processes=$((training_processes + 1))
    is_integer "${etimes}" && emit_metric "nixl_job_process_uptime_seconds" "${etimes}" "pid=${pid}" "cmdline_summary=${summary}"
    is_number "${cpu}" && emit_metric "nixl_job_process_cpu_percent" "${cpu}" "pid=${pid}" "cmdline_summary=${summary}"
    is_integer "${rss}" && emit_metric "nixl_job_process_mem_rss_bytes" "$((rss * 1024))" "pid=${pid}" "cmdline_summary=${summary}"
    ;;
  esac
done < <("${PS_CMD}" -eo pid=,etimes=,pcpu=,rss=,args= 2>/dev/null || true)
emit_metric "nixl_job_training_processes_total" "${training_processes}"

max_checkpoint_age=0
total_recent_checkpoints=0
read -r -a checkpoint_roots <<<"${CHECKPOINT_DIRS}"
for checkpoint_root in "${checkpoint_roots[@]}"; do
  [[ -d "${checkpoint_root}" ]] || continue
  recent_count=0
  newest_mtime=0
  while IFS= read -r checkpoint_file; do
    [[ -n "${checkpoint_file}" ]] || continue
    age_seconds="$(safe_age_seconds "${checkpoint_file}")"
    if awk -v age="${age_seconds}" -v window="${CHECKPOINT_WINDOW_SECONDS}" 'BEGIN { exit !(age <= window) }'; then
      recent_count=$((recent_count + 1))
      total_recent_checkpoints=$((total_recent_checkpoints + 1))
    fi
    file_mtime="$("${STAT_CMD}" -c '%Y' "${checkpoint_file}" 2>/dev/null || true)"
    if is_integer "${file_mtime}" && ((file_mtime > newest_mtime)); then
      newest_mtime="${file_mtime}"
    fi
  done < <("${FIND_CMD}" "${checkpoint_root}" -maxdepth 4 -type f \( -name '*.pt' -o -name '*.safetensors' -o -name '*.ckpt' -o -name '*.bin' \) 2>/dev/null || true)

  checkpoint_age=0
  if is_integer "${newest_mtime}" && ((newest_mtime > 0)); then
    checkpoint_age="$(awk -v now="${NOW_EPOCH}" -v mtime="${newest_mtime}" 'BEGIN {
      age = now - mtime
      if (age < 0) {
        age = 0
      }
      printf "%.0f\n", age
    }')"
  fi
  emit_metric "nixl_job_checkpoint_files_recent" "${recent_count}" "dir=${checkpoint_root}"
  emit_metric "nixl_job_checkpoint_last_write_age_seconds" "${checkpoint_age}" "dir=${checkpoint_root}"
  if ((checkpoint_age > max_checkpoint_age)); then
    max_checkpoint_age="${checkpoint_age}"
  fi
done

any_log_progress=0
any_recent_log_update=0
most_recent_log_age=0
read -r -a log_roots <<<"${LOG_DIRS}"
for log_root in "${log_roots[@]}"; do
  [[ -d "${log_root}" ]] || continue
  while IFS= read -r log_file; do
    [[ -n "${log_file}" ]] || continue
    log_age="$(safe_age_seconds "${log_file}")"
    last_step="$(extract_last_step "${log_file}")"
    emit_metric "nixl_job_log_last_step" "${last_step}" "logfile=${log_file}"
    emit_metric "nixl_job_log_last_update_age_seconds" "${log_age}" "logfile=${log_file}"
    if awk -v age="${log_age}" -v threshold="${STALL_THRESHOLD_SECONDS}" 'BEGIN { exit !(age <= threshold) }'; then
      any_recent_log_update=1
    fi

    state_key="$(log_state_key "${log_file}")"
    previous_step="$(read_state_step "${state_key}")"
    progress_updated="$(read_state_progress_updated "${state_key}")"
    if ! is_integer "${progress_updated}"; then
      progress_updated=0
    fi
    if awk -v step="${last_step}" -v previous="${previous_step}" 'BEGIN { exit !(step > previous) }'; then
      progress_updated="${NOW_EPOCH}"
    elif ((progress_updated == 0)) && awk -v step="${last_step}" 'BEGIN { exit !(step > 0) }'; then
      progress_updated="${NOW_EPOCH}"
    fi
    write_state "${state_key}" "${last_step}" "${progress_updated}"

    if awk -v updated="${progress_updated}" -v now="${NOW_EPOCH}" -v threshold="${STALL_THRESHOLD_SECONDS}" 'BEGIN { exit !((updated > 0) && ((now - updated) <= threshold)) }'; then
      any_log_progress=1
    fi
    if ((most_recent_log_age == 0 || log_age < most_recent_log_age)); then
      most_recent_log_age="${log_age}"
    fi
  done < <("${FIND_CMD}" "${log_root}" -maxdepth 4 -type f \( -name '*.log' -o -name 'stdout' -o -name 'nohup.out' -o -name 'slurm-*.out' \) 2>/dev/null || true)
done

gpu_active="$(recent_gpu_activity)"
stall_suspected=0
if ((training_processes > 0)) && ((gpu_active > 0)) && ((total_recent_checkpoints == 0)) && ((any_log_progress == 0)) && ((any_recent_log_update == 0)); then
  stall_suspected=1
fi
emit_metric "nixl_job_stall_suspected" "${stall_suspected}"

stall_file="${STATE_DIR}/stall.state"
stall_duration=0
mkdir -p "${STATE_DIR}"
if ((stall_suspected == 1)); then
  if [[ -r "${stall_file}" ]]; then
    first_seen="$(safe_read_file "${stall_file}" || true)"
  else
    first_seen="${NOW_EPOCH}"
    printf '%s\n' "${first_seen}" >"${stall_file}"
  fi
  if is_integer "${first_seen}"; then
    stall_duration="$(awk -v now="${NOW_EPOCH}" -v first_seen="${first_seen}" 'BEGIN {
      age = now - first_seen
      if (age < 0) {
        age = 0
      }
      printf "%.0f\n", age
    }')"
  fi
else
  rm -f -- "${stall_file}"
fi
emit_metric "nixl_job_stall_duration_seconds" "${stall_duration}"

prom_end_scrape "nixl_job_scrape_success"
