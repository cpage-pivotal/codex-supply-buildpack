#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
version=$(tr -d '[:space:]' < "${repo_dir}/VERSION")
output="${repo_dir}/build/codex_supply_buildpack-v${version}.zip"

mkdir -p "${repo_dir}/build"
rm -f "${output}"
(
  cd "${repo_dir}"
  zip -q -r "${output}" \
    bin config dependencies lib VERSION LICENSE SECURITY.md README.md \
    -x 'dependencies/codex-*' 'dependencies/node-*' 'dependencies/jq-*' '*.DS_Store'
)
unzip -t "${output}" >/dev/null
echo "${output}"
