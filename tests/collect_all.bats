#!/usr/bin/env bats
# shellcheck disable=SC2154  # Bats populates TEST_TMPDIR/ROOT_DIR via setup hooks and loaded helpers.

load './helpers.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "collect-all continues when one exporter fails" {
  local work_dir="${TEST_TMPDIR}/work"
  local out_dir="${TEST_TMPDIR}/collect-out"
  mkdir -p "${work_dir}" "${out_dir}"
  cp -R "${ROOT_DIR}/scripts" "${work_dir}/scripts"
  cat >"${work_dir}/scripts/cpu-irq-exporter.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "simulated failure" >&2
exit 23
EOF
  chmod +x "${work_dir}/scripts/cpu-irq-exporter.sh"

  while IFS= read -r assignment; do
    local name="${assignment%%=*}"
    local value="${assignment#*=}"
    export "${name}=${value}"
  done < <(common_env)

  run env SCRIPT_DIR="${work_dir}/scripts" OUT_DIR="${out_dir}" EXPORTERS="nixl_host_mem nixl_cpu_irq" bash "${ROOT_DIR}/scripts/collect-all.sh"
  [[ "${status}" -eq 0 ]]
  [[ -f "${out_dir}/nixl_host_mem.prom" ]]
  [[ -f "${out_dir}/nixl_cpu_irq.prom" ]]
  grep -Eq 'ai_host_exporter_last_run_success\{exporter="nixl_host_mem"\} 1 [0-9]+$' "${out_dir}/nixl_host_mem.prom"
  grep -Eq 'ai_host_exporter_last_run_success\{exporter="nixl_cpu_irq"\} 0 [0-9]+$' "${out_dir}/nixl_cpu_irq.prom"
}

@test "collect-all cleans temporary files" {
  local out_dir="${TEST_TMPDIR}/collect-clean"
  mkdir -p "${out_dir}"

  while IFS= read -r assignment; do
    local name="${assignment%%=*}"
    local value="${assignment#*=}"
    export "${name}=${value}"
  done < <(common_env)

  run env OUT_DIR="${out_dir}" EXPORTERS="nixl_host_mem" bash "${ROOT_DIR}/scripts/collect-all.sh"
  [[ "${status}" -eq 0 ]]
  run find "${out_dir}" -maxdepth 1 -name '.ai-host-observability.*'
  [[ "${status}" -eq 0 ]]
  [[ -z "${output}" ]]
}

@test "collect-all respects requested OUT_DIR" {
  local out_dir="${TEST_TMPDIR}/collect-respects-out-dir"
  mkdir -p "${out_dir}"

  while IFS= read -r assignment; do
    local name="${assignment%%=*}"
    local value="${assignment#*=}"
    export "${name}=${value}"
  done < <(common_env)

  run env OUT_DIR="${out_dir}" EXPORTERS="nixl_gpu" bash "${ROOT_DIR}/scripts/collect-all.sh"
  [[ "${status}" -eq 0 ]]
  [[ -f "${out_dir}/nixl_gpu.prom" ]]
  [[ -s "${out_dir}/nixl_gpu.prom" ]]
}
