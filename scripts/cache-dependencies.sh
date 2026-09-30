#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
arch=${1:-}
destination=${2:-"${repo_dir}/build/cache-${arch}"}
manifest="${repo_dir}/config/dependencies.json"

case "${arch}" in
  amd64|arm64) ;;
  *)
    echo "Usage: $0 <amd64|arm64> [destination]" >&2
    exit 2
    ;;
esac

source "${repo_dir}/lib/installer.sh"
mkdir -p "${destination}"

for dependency in codex codex-acp node jq; do
  filename=$(dependency_value "${manifest}" "${dependency}" "${arch}" filename)
  url=$(dependency_value "${manifest}" "${dependency}" "${arch}" url)
  expected=$(dependency_value "${manifest}" "${dependency}" "${arch}" sha256)
  download_atomic "${url}" "${destination}/${filename}" "${expected}"
done

echo "${destination}"
