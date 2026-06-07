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
ROCM_SMI=${FIXTURE_DIR}/bin/rocm-smi
INTEL_GPU_TOP=${FIXTURE_DIR}/bin/intel_gpu_top
JOURNALCTL=${FIXTURE_DIR}/bin/journalctl
INTERESTING_DRIVERS_REGEX=.*
NET_IFACES=eth0
PATH=${FIXTURE_DIR}/bin:${PATH}
EOF
}

run_exporter_direct() {
  local script_name="$1"
  local output_file="$2"
  while IFS= read -r assignment; do
    local name="${assignment%%=*}"
    local value="${assignment#*=}"
    export "${name}=${value}"
  done < <(common_env)

  bash "${ROOT_DIR}/scripts/${script_name}" >"${output_file}"
}

run_exporter_direct_missing_roots() {
  local script_name="$1"
  local output_file="$2"
  while IFS= read -r assignment; do
    local name="${assignment%%=*}"
    local value="${assignment#*=}"
    export "${name}=${value}"
  done < <(common_env)

  PROC_ROOT="/nonexistent" \
    SYS_ROOT="/nonexistent" \
    DEBUGFS_ROOT="/nonexistent" \
    bash "${ROOT_DIR}/scripts/${script_name}" >"${output_file}"
}

run_collect_one() {
  local exporter="$1"
  local proc_root="$2"
  local out_dir="$3"

  while IFS= read -r assignment; do
    local name="${assignment%%=*}"
    local value="${assignment#*=}"
    export "${name}=${value}"
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

assert_metric_present() {
  local pattern="$1"
  local file="$2"
  grep -Fq -- "$pattern" "$file"
}

assert_wrapper_failure() {
  local exporter="$1"
  local file="$2"
  grep -Eq "ai_host_exporter_last_run_success\\{exporter=\"${exporter}\"\\} 0 [0-9]+$" "$file"
}

assert_scrape_success_zero() {
  local metric_name="$1"
  local file="$2"
  grep -Eq "^${metric_name}(\\{[^}]*\\})? 0 [0-9]+$" "$file"
}

assert_prom_sample_valid() {
  local file="$1"
  python3 - "$file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if not text.strip():
    raise SystemExit("empty file")
if "\r" in text:
    raise SystemExit("CRLF found")
if text.count("\n") < 2:
    raise SystemExit("unexpected single-line formatting")

help_seen = {}
type_seen = {}
metric_line = re.compile(r'^[a-zA-Z_:][a-zA-Z0-9_:]*(\{[^}]*\})?\s+[-+]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][-+]?\d+)?(?:\s+[-+]?\d+)?$')
label_shape = re.compile(r'^[a-zA-Z_][a-zA-Z0-9_]*="(?:[^"\\]|\\.)*"$')

for line in text.splitlines():
    if not line.strip():
        continue
    if line.startswith("# HELP "):
        parts = line.split(" ", 3)
        if len(parts) < 4:
            raise SystemExit(f"bad HELP line: {line}")
        help_seen[parts[2]] = help_seen.get(parts[2], 0) + 1
        continue
    if line.startswith("# TYPE "):
        parts = line.split(" ", 3)
        if len(parts) != 4 or parts[3] not in {"counter", "gauge", "histogram", "summary", "untyped"}:
            raise SystemExit(f"bad TYPE line: {line}")
        type_seen[parts[2]] = type_seen.get(parts[2], 0) + 1
        continue
    if not metric_line.match(line):
        raise SystemExit(f"bad metric line: {line}")
    if "{" in line:
        labels = line.split("{", 1)[1].split("}", 1)[0]
        if labels:
            for chunk in labels.split(","):
                if not label_shape.match(chunk):
                    raise SystemExit(f"bad label chunk: {chunk}")

for name, count in help_seen.items():
    if count != 1:
        raise SystemExit(f"duplicate HELP for {name}")
    if type_seen.get(name, 0) != 1:
        raise SystemExit(f"missing TYPE for {name}")

for name, count in type_seen.items():
    if count != 1:
        raise SystemExit(f"duplicate TYPE for {name}")
    if help_seen.get(name, 0) != 1:
        raise SystemExit(f"missing HELP for {name}")
PY
}
