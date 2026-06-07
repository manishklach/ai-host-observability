#!/usr/bin/env bats
# shellcheck disable=SC2034,SC2154  # Bats uses locals inside the inline shell, and ROOT_DIR is populated by the shared test setup.

load './helpers.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "operator-facing text artifacts are stored as real multi-line files" {
  local patterns=(
    "README.md"
    "Makefile"
    ".github/workflows/*.yml"
    "deploy/systemd/*.service"
    "deploy/systemd/*.timer"
    "scripts/*.sh"
    "scripts/lib/*.sh"
    "tests/*.sh"
    "tests/*.bats"
    "docs/**/*.md"
    "prometheus/alerts.yml"
    "grafana/*.json"
    "examples/sample-output/*.prom"
  )
  local file
  local count
  local matched=0

  run bash -lc '
    set -euo pipefail
    shopt -s globstar nullglob
    cd "$1"
    shift
    for pattern in "$@"; do
      for file in $pattern; do
        matched=1
        count="$(wc -l < "$file")"
        if [[ "$count" -le 1 ]]; then
          printf "not-multiline %s %s\n" "$file" "$count"
          exit 1
        fi
        if grep -q $'\''\r'\'' "$file"; then
          printf "contains-cr %s\n" "$file"
          exit 1
        fi
      done
    done
  ' _ "${ROOT_DIR}" "${patterns[@]}"
  [[ "${status}" -eq 0 ]]
}
