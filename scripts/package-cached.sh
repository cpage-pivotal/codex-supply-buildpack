#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
arch=${1:-}
cached_dir=${2:-}
version=$(tr -d '[:space:]' < "${repo_dir}/VERSION")
output="${repo_dir}/build/codex_supply_buildpack-cached-v${version}-${arch}.zip"
stage_dir=$(mktemp -d)
trap 'rm -rf "${stage_dir}"' EXIT

case "${arch}" in
  amd64|arm64) ;;
  *)
    echo "Usage: $0 <amd64|arm64> <cached-dependency-directory>" >&2
    exit 2
    ;;
esac

[ -d "${cached_dir}" ] || {
  echo "Cached dependency directory not found: ${cached_dir}" >&2
  exit 1
}

source "${repo_dir}/lib/installer.sh"
mkdir -p "${stage_dir}/buildpack"
(
  cd "${repo_dir}"
  cp -R bin config dependencies lib VERSION LICENSE SECURITY.md README.md \
    "${stage_dir}/buildpack/"
)
for dependency in codex codex-code-mode-host codex-acp node jq; do
  filename=$(dependency_value "${repo_dir}/config/dependencies.json" \
    "${dependency}" "${arch}" filename)
  expected=$(dependency_value "${repo_dir}/config/dependencies.json" \
    "${dependency}" "${arch}" sha256)
  verify_sha256 "${cached_dir}/${filename}" "${expected}"
  cp "${cached_dir}/${filename}" "${stage_dir}/buildpack/dependencies/${filename}"
done
(
  cd "${stage_dir}/buildpack"
  zip -q -r "${output}" .
)
unzip -t "${output}" >/dev/null
echo "${output}"
