#!/usr/bin/env bats
# shellcheck disable=SC2154  # Bats populates TEST_TMPDIR/FIXTURE_DIR/ROOT_DIR via setup hooks and loaded helpers.

load './helpers.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "nixl_job direct fixture run emits process, checkpoint, and log metrics" {
  out_dir="${TEST_TMPDIR}/job-prom"
  checkpoint_dir="${TEST_TMPDIR}/checkpoints"
  log_dir="${TEST_TMPDIR}/logs"
  mkdir -p "${out_dir}" "${checkpoint_dir}" "${log_dir}"
  cp "${FIXTURE_DIR}/prom-input/gpu.prom" "${out_dir}/gpu.prom"

  checkpoint_file="${checkpoint_dir}/model-001.ckpt"
  log_file="${log_dir}/train.log"
  printf 'checkpoint\n' >"${checkpoint_file}"
  printf 'epoch 1\nstep 42\n500/1000\n' >"${log_file}"

  run env OUT_DIR="${out_dir}" PS_CMD="${FIXTURE_DIR}/bin/ps-training" CHECKPOINT_DIRS="${checkpoint_dir}" LOG_DIRS="${log_dir}" NOW_EPOCH="$(date +%s)" bash "${ROOT_DIR}/scripts/job-heartbeat-exporter.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'nixl_job_training_processes_total 1 '* ]]
  [[ "${output}" == *"nixl_job_checkpoint_files_recent{dir=\"${checkpoint_dir}\"} 1 "* ]]
  [[ "${output}" == *"nixl_job_log_last_step{logfile=\"${log_file}\"} 500 "* ]]
}

@test "nixl_job missing ps command emits scrape success 0" {
  run env OUT_DIR="${TEST_TMPDIR}/job-missing" PS_CMD="${TEST_TMPDIR}/missing-ps" bash "${ROOT_DIR}/scripts/job-heartbeat-exporter.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *'nixl_job_scrape_success 0 '* ]]
}

@test "nixl_job respects OUT_DIR via collect-all" {
  out_dir="${TEST_TMPDIR}/job-out"
  checkpoint_dir="${TEST_TMPDIR}/job-out-checkpoints"
  log_dir="${TEST_TMPDIR}/job-out-logs"
  mkdir -p "${out_dir}" "${checkpoint_dir}" "${log_dir}"
  cp "${FIXTURE_DIR}/prom-input/gpu.prom" "${out_dir}/gpu.prom"
  printf 'checkpoint\n' >"${checkpoint_dir}/latest.pt"
  printf 'step 10\n' >"${log_dir}/stdout"

  run env OUT_DIR="${out_dir}" EXPORTERS="nixl_job" PS_CMD="${FIXTURE_DIR}/bin/ps-training" CHECKPOINT_DIRS="${checkpoint_dir}" LOG_DIRS="${log_dir}" NOW_EPOCH="$(date +%s)" bash "${ROOT_DIR}/scripts/collect-all.sh"
  [[ "${status}" -eq 0 ]]
  [[ -f "${out_dir}/nixl_job.prom" ]]
  grep -Fq 'nixl_job_training_processes_total 1' "${out_dir}/nixl_job.prom"
}
