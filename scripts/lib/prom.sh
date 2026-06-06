#!/usr/bin/env bash

if [[ -n "${AI_HOST_PROM_LIB_SOURCED:-}" ]]; then
  return 0
fi
AI_HOST_PROM_LIB_SOURCED=1

PROM_TIMESTAMP="${PROM_TIMESTAMP:-$(date +%s)}"
PROM_SCRAPE_METRIC=""

prom_set_timestamp() {
  PROM_TIMESTAMP="${1:-$(date +%s)}"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

safe_read_file() {
  local path="$1"
  [[ -r "$path" ]] || return 1
  cat -- "$path"
}

is_integer() {
  [[ "${1:-}" =~ ^-?[0-9]+$ ]]
}

is_number() {
  [[ "${1:-}" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

escape_label_value() {
  local value="${1-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '%s' "$value"
}

emit_help() {
  local name="$1"
  local type="$2"
  local help="$3"
  printf '# HELP %s %s\n' "$name" "$help"
  printf '# TYPE %s %s\n' "$name" "$type"
}

emit_metric() {
  local name="$1"
  local value="$2"
  shift 2

  if (($# > 0)); then
    local rendered=()
    local label key raw
    for label in "$@"; do
      key="${label%%=*}"
      raw="${label#*=}"
      rendered+=("${key}=\"$(escape_label_value "$raw")\"")
    done
    printf '%s{%s} %s %s\n' "$name" "$(IFS=,; printf '%s' "${rendered[*]}")" "$value" "$PROM_TIMESTAMP"
  else
    printf '%s %s %s\n' "$name" "$value" "$PROM_TIMESTAMP"
  fi
}

prom_begin_scrape() {
  PROM_SCRAPE_METRIC="$1"
  emit_help "$1" gauge "$2"
  emit_metric "$1" 0
}

prom_end_scrape() {
  local metric_name="${1:-${PROM_SCRAPE_METRIC:-}}"
  [[ -n "$metric_name" ]] || return 0
  emit_metric "$metric_name" 1
}

