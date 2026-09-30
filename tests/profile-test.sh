#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "${repo_dir}/tests/test-helper.sh"
source "${repo_dir}/lib/installer.sh"
source "${repo_dir}/lib/environment.sh"

build_dir="${TEST_TMP}/app"
deps_root="${TEST_TMP}/deps"
index=3
mkdir -p "${build_dir}" "${deps_root}/${index}"

setup_environment "${deps_root}/${index}" "${build_dir}" "${index}"
create_config_file "${deps_root}/${index}" "${repo_dir}"

profile="${build_dir}/.profile.d/codex-env.sh"
assert_eq 4 "$(grep -c . "${profile}")" \
  "profile should set PATH, CODEX_ACP_CLI_PATH and CODEX_PATH only"

export DEPS_DIR="${deps_root}"
original_path=${PATH}
unset CODEX_ACP_CLI_PATH CODEX_PATH
# shellcheck source=/dev/null
source "${profile}"

assert_eq "${deps_root}/${index}/bin/codex-acp" "${CODEX_ACP_CLI_PATH}"
assert_eq "${deps_root}/${index}/bin/codex" "${CODEX_PATH}"
case "${PATH}" in
  "${deps_root}/${index}/bin:${original_path}") ;;
  *) fail "generated runtime PATH did not expand DEPS_DIR and PATH" ;;
esac

manifest="${repo_dir}/config/dependencies.json"
config="${deps_root}/${index}/config.yml"
assert_file_contains "${config}" "name: codex-supply-buildpack"
assert_file_contains "${config}" \
  "version: $(jq -r '.dependencies["codex-acp"].version' "${manifest}")"
assert_file_contains "${config}" \
  "codex_version: $(jq -r '.dependencies.codex.version' "${manifest}")"
assert_file_contains "${config}" "cli_path: ${deps_root}/${index}/bin/codex-acp"
assert_file_contains "${config}" "codex_path: ${deps_root}/${index}/bin/codex"

if "${repo_dir}/bin/detect" "${build_dir}"; then
  fail "a supply-only buildpack must not auto-detect"
fi

echo "profile-test: PASS"
