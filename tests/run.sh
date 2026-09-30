#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for test_file in "${repo_dir}"/tests/*-test.sh; do
  echo "Running $(basename "${test_file}")"
  "${test_file}"
done
