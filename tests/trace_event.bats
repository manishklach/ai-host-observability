#!/usr/bin/env bats
# shellcheck disable=SC2154  # Bats populates TEST_TMPDIR/FIXTURE_DIR/ROOT_DIR via setup hooks and loaded helpers.

load './helpers.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "nixl_trace direct fixture run emits tracefs inventory and perf metrics" {
  run env PROC_ROOT="${FIXTURE_DIR}/proc" SYS_ROOT="${FIXTURE_DIR}/sys" TRACING_ROOT="${FIXTURE_DIR}/sys/kernel/tracing" bash "${ROOT_DIR}/scripts/trace-event-exporter.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'nixl_trace_events_enabled_total{subsystem="mm"} 1 '* ]]
  [[ "${output}" == *'nixl_trace_function_hit_total{function="schedule"} 1200 '* ]]
  [[ "${output}" == *'nixl_perf_event_paranoid 1 '* ]]
}

@test "nixl_trace missing tracefs emits scrape success 0" {
  run env PROC_ROOT="${FIXTURE_DIR}/proc" TRACING_ROOT="${TEST_TMPDIR}/missing-tracing" bash "${ROOT_DIR}/scripts/trace-event-exporter.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'nixl_trace_scrape_success 0 '* ]]
}

@test "nixl_trace respects OUT_DIR via collect-all" {
  out_dir="${TEST_TMPDIR}/trace-out"
  mkdir -p "${out_dir}"
  run env PROC_ROOT="${FIXTURE_DIR}/proc" SYS_ROOT="${FIXTURE_DIR}/sys" TRACING_ROOT="${FIXTURE_DIR}/sys/kernel/tracing" OUT_DIR="${out_dir}" EXPORTERS="nixl_trace" bash "${ROOT_DIR}/scripts/collect-all.sh"
  [[ "${status}" -eq 0 ]]
  [[ -f "${out_dir}/nixl_trace.prom" ]]
  grep -Fq 'nixl_trace_mm_page_alloc_total 900' "${out_dir}/nixl_trace.prom"
}
