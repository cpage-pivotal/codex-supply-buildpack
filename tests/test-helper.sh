#!/usr/bin/env bash
set -euo pipefail

TEST_TMP=$(mktemp -d)
trap 'rm -rf "${TEST_TMP}"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local expected=$1
  local actual=$2
  local message=${3:-"values differ"}
  [ "${expected}" = "${actual}" ] || fail "${message}: expected '${expected}', got '${actual}'"
}

assert_file_contains() {
  local file=$1
  local pattern=$2
  grep -Fq "${pattern}" "${file}" || fail "${file} does not contain ${pattern}"
}

assert_not_contains() {
  local value=$1
  local pattern=$2
  [[ "${value}" != *"${pattern}"* ]] || fail "unexpected value was exposed: ${pattern}"
}
