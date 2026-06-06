#!/usr/bin/env bash

setup_test_env() {
  export ROOT_DIR
  ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
  export FIXTURE_DIR="${ROOT_DIR}/tests/fixtures"
  export TEST_TMPDIR
  TEST_TMPDIR="$(mktemp -d)"
  export EMPTY_PROC_ROOT="${TEST_TMPDIR}/missing-proc"
  export EMPTY_OUT_DIR="${TEST_TMPDIR}/out"
  mkdir -p "${EMPTY_OUT_DIR}"
}

teardown_test_env() {
  rm -rf -- "${TEST_TMPDIR}"
}

common_env() {
  cat <<EOF
PROC_ROOT=${FIXTURE_DIR}/proc
SYS_ROOT=${FIXTURE_DIR}/sys
DEBUGFS_ROOT=${FIXTURE_DIR}/debugfs
CGROUP_PATH=${FIXTURE_DIR}/cgroup/workload
ETHTOOL=${FIXTURE_DIR}/bin/ethtool
NVIDIA_SMI=${FIXTURE_DIR}/bin/nvidia-smi
JOURNALCTL=${FIXTURE_DIR}/bin/journalctl
INTERESTING_DRIVERS_REGEX=.*
NET_IFACES=eth0
EOF
}

run_exporter_direct() {
  local script_name="$1"
  local output_file="$2"
  while IFS= read -r assignment; do
    export "$assignment"
  done < <(common_env)

  bash "${ROOT_DIR}/scripts/${script_name}" >"${output_file}"
}

run_collect_one() {
  local exporter="$1"
  local proc_root="$2"
  local out_dir="$3"

  while IFS= read -r assignment; do
    export "$assignment"
  done < <(common_env)

  PROC_ROOT="${proc_root}" \
  OUT_DIR="${out_dir}" \
  EXPORTERS="${exporter}" \
  bash "${ROOT_DIR}/scripts/collect-all.sh"
}

assert_valid_metric_line() {
  local file="$1"
  grep -Eq '^[a-z_]+(\{.*\})? [-0-9.]+ [0-9]+$' "$file"
}

assert_wrapper_failure() {
  local exporter="$1"
  local file="$2"
  grep -Eq "ai_host_exporter_last_run_success\\{exporter=\"${exporter}\"\\} 0 [0-9]+$" "$file"
}

