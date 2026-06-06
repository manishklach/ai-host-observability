#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/tests/fixtures"
WORK_DIR="$(mktemp -d)"
OUT_DIR="$(mktemp -d)"

cleanup() {
  rm -rf -- "$WORK_DIR" "$OUT_DIR"
}
trap cleanup EXIT

cp -R "${ROOT_DIR}/scripts" "${WORK_DIR}/scripts"
cat >"${WORK_DIR}/scripts/cpu-irq-exporter.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "simulated failure" >&2
exit 23
EOF
chmod +x "${WORK_DIR}/scripts/cpu-irq-exporter.sh"

(
  cd "$ROOT_DIR"
  OUT_DIR="$OUT_DIR" \
  SCRIPT_DIR="${WORK_DIR}/scripts" \
  EXPORTERS="nixl_host_mem nixl_cpu_irq" \
  PROC_ROOT="${FIXTURE_DIR}/proc" \
  SYS_ROOT="${FIXTURE_DIR}/sys" \
  DEBUGFS_ROOT="${FIXTURE_DIR}/debugfs" \
  CGROUP_PATH="${FIXTURE_DIR}/cgroup/workload" \
  ETHTOOL="${FIXTURE_DIR}/bin/ethtool" \
  NVIDIA_SMI="${FIXTURE_DIR}/bin/nvidia-smi" \
  JOURNALCTL="${FIXTURE_DIR}/bin/journalctl" \
  bash scripts/collect-all.sh
)

grep -Eq 'ai_host_exporter_last_run_success\{exporter="nixl_host_mem"\} 1 ' "${OUT_DIR}/nixl_host_mem.prom"
grep -Eq 'ai_host_exporter_last_run_success\{exporter="nixl_cpu_irq"\} 0 ' "${OUT_DIR}/nixl_cpu_irq.prom"
grep -Eq 'ai_host_exporter_last_run_error\{exporter="nixl_cpu_irq",error="simulated failure"\} 1 ' "${OUT_DIR}/nixl_cpu_irq.prom"

if find "$OUT_DIR" -maxdepth 1 -name '.ai-host-observability.*' | grep -q .; then
  echo "temporary files leaked into OUT_DIR" >&2
  exit 1
fi

echo "test_collect_all.sh: ok"

