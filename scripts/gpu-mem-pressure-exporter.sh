#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC2250,SC2310,SC2312  # Compact conditionals and fallback reads are intentional in exporter code.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/prom.sh
source "${SCRIPT_DIR}/lib/prom.sh"

NVIDIA_SMI="${NVIDIA_SMI:-nvidia-smi}"

to_bytes_from_mib() {
  awk -v value="$1" 'BEGIN { printf "%.0f", value * 1024 * 1024 }'
}

prom_begin_scrape "nixl_gpumem_scrape_success" "Whether the GPU memory pressure exporter completed successfully."
if ! command_exists "${NVIDIA_SMI}"; then
  exit 0
fi

emit_help "nixl_gpu_process_memory_bytes" gauge "Per-process GPU memory footprint in bytes."
emit_help "nixl_gpu_process_count" gauge "Number of processes using a GPU."
emit_help "nixl_gpu_memory_free_bytes" gauge "Free GPU memory in bytes."
emit_help "nixl_gpu_memory_reserved_bytes" gauge "GPU memory reserved by the driver in bytes."
emit_help "nixl_gpu_memory_fragmentation_ratio" gauge "Reserved-to-total GPU memory ratio."
emit_help "nixl_gpu_compute_mode" gauge "Current GPU compute mode label."
emit_help "nixl_gpu_mig_mode" gauge "Current GPU MIG mode label."
emit_help "nixl_gpu_retired_pages_sbe" gauge "Retired single-bit ECC pages."
emit_help "nixl_gpu_retired_pages_dbe" gauge "Retired double-bit ECC pages."
emit_help "nixl_gpu_retired_pages_pending" gauge "GPU pages pending retirement."
emit_help "nixl_gpu_remapped_rows_correctable" gauge "Correctable remapped rows."
emit_help "nixl_gpu_remapped_rows_uncorrectable" gauge "Uncorrectable remapped rows."
emit_help "nixl_gpu_remapped_rows_pending" gauge "Pending remapped rows."

declare -A gpu_index_by_uuid=()
declare -A gpu_process_count=()

while IFS=',' read -r index uuid mem_used mem_total mem_free compute_mode mig_mode retired_sbe retired_dbe retired_pending remapped_correctable remapped_uncorrectable remapped_pending; do
  index="$(xargs <<<"${index}")"
  uuid="$(xargs <<<"${uuid}")"
  mem_used="$(xargs <<<"${mem_used}")"
  mem_total="$(xargs <<<"${mem_total}")"
  mem_free="$(xargs <<<"${mem_free}")"
  compute_mode="$(xargs <<<"${compute_mode}")"
  mig_mode="$(xargs <<<"${mig_mode}")"
  retired_sbe="$(xargs <<<"${retired_sbe}")"
  retired_dbe="$(xargs <<<"${retired_dbe}")"
  retired_pending="$(xargs <<<"${retired_pending}")"
  remapped_correctable="$(xargs <<<"${remapped_correctable}")"
  remapped_uncorrectable="$(xargs <<<"${remapped_uncorrectable}")"
  remapped_pending="$(xargs <<<"${remapped_pending}")"

  gpu_index_by_uuid["${uuid}"]="${index}"
  gpu_process_count["${uuid}"]=0

  if is_number "${mem_total}" && is_number "${mem_used}" && is_number "${mem_free}"; then
    reserved_bytes="$(awk -v total="${mem_total}" -v used="${mem_used}" -v free="${mem_free}" 'BEGIN {
      reserved = total - used - free
      if (reserved < 0) {
        reserved = 0
      }
      printf "%.0f", reserved * 1024 * 1024
    }')"
    fragmentation_ratio="$(awk -v total="${mem_total}" -v reserved="${reserved_bytes}" 'BEGIN {
      if (total <= 0) {
        print 0
      } else {
        printf "%.6f", reserved / (total * 1024 * 1024)
      }
    }')"
    emit_metric "nixl_gpu_memory_free_bytes" "$(to_bytes_from_mib "${mem_free}")" "index=${index}" "uuid=${uuid}"
    emit_metric "nixl_gpu_memory_reserved_bytes" "${reserved_bytes}" "index=${index}" "uuid=${uuid}"
    emit_metric "nixl_gpu_memory_fragmentation_ratio" "${fragmentation_ratio}" "index=${index}" "uuid=${uuid}"
  fi

  [[ -n "${compute_mode}" ]] && emit_metric "nixl_gpu_compute_mode" 1 "index=${index}" "uuid=${uuid}" "mode=${compute_mode}"
  [[ -n "${mig_mode}" ]] && emit_metric "nixl_gpu_mig_mode" 1 "index=${index}" "uuid=${uuid}" "mode=${mig_mode}"
  is_integer "${retired_sbe}" && emit_metric "nixl_gpu_retired_pages_sbe" "${retired_sbe}" "index=${index}" "uuid=${uuid}"
  is_integer "${retired_dbe}" && emit_metric "nixl_gpu_retired_pages_dbe" "${retired_dbe}" "index=${index}" "uuid=${uuid}"
  is_integer "${retired_pending}" && emit_metric "nixl_gpu_retired_pages_pending" "${retired_pending}" "index=${index}" "uuid=${uuid}"
  is_integer "${remapped_correctable}" && emit_metric "nixl_gpu_remapped_rows_correctable" "${remapped_correctable}" "index=${index}" "uuid=${uuid}"
  is_integer "${remapped_uncorrectable}" && emit_metric "nixl_gpu_remapped_rows_uncorrectable" "${remapped_uncorrectable}" "index=${index}" "uuid=${uuid}"
  is_integer "${remapped_pending}" && emit_metric "nixl_gpu_remapped_rows_pending" "${remapped_pending}" "index=${index}" "uuid=${uuid}"
done < <("${NVIDIA_SMI}" --query-gpu=index,uuid,memory.used,memory.total,memory.free,compute_mode,mig.mode.current,retired_pages.single_bit_ecc.count,retired_pages.double_bit.count,retired_pages.pending,remapped_rows.correctable,remapped_rows.uncorrectable,remapped_rows.pending --format=csv,noheader,nounits 2>/dev/null || true)

while IFS=',' read -r gpu_uuid pid used_gpu_memory process_name; do
  gpu_uuid="$(xargs <<<"${gpu_uuid}")"
  pid="$(xargs <<<"${pid}")"
  used_gpu_memory="$(xargs <<<"${used_gpu_memory}")"
  process_name="$(xargs <<<"${process_name}")"
  index="${gpu_index_by_uuid["${gpu_uuid}"]:-}"
  if [[ -n "${index}" ]] && is_integer "${pid}" && is_number "${used_gpu_memory}"; then
    emit_metric "nixl_gpu_process_memory_bytes" "$(to_bytes_from_mib "${used_gpu_memory}")" "index=${index}" "uuid=${gpu_uuid}" "pid=${pid}" "process_name=${process_name}"
    gpu_process_count["${gpu_uuid}"]=$((${gpu_process_count["${gpu_uuid}"]:-0} + 1))
  fi
done < <("${NVIDIA_SMI}" --query-compute-apps=gpu_uuid,pid,used_gpu_memory,process_name --format=csv,noheader,nounits 2>/dev/null || true)

for uuid in "${!gpu_index_by_uuid[@]}"; do
  emit_metric "nixl_gpu_process_count" "${gpu_process_count["${uuid}"]:-0}" "index=${gpu_index_by_uuid["${uuid}"]}" "uuid=${uuid}"
done

prom_end_scrape "nixl_gpumem_scrape_success"
