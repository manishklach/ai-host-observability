#!/usr/bin/env bats

load './helpers.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "sample Prometheus outputs are syntactically valid" {
  local sample_dir="${ROOT_DIR}/examples/sample-output"
  local file

  for file in "${sample_dir}"/*.prom; do
    [ -s "${file}" ]
    run assert_prom_sample_valid "${file}"
    [ "$status" -eq 0 ]
  done
}
