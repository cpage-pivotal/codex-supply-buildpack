#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "${repo_dir}/tests/test-helper.sh"
source "${repo_dir}/lib/installer.sh"

# Stand-ins for the three archives. The fake node runs its script argument as a
# shell script, so a shell script can stand in for codex-acp's index.js. The
# scripts' own variables expand when they run, not here.
fake_node_root="${TEST_TMP}/node-root"
mkdir -p "${fake_node_root}/node-v9.9.9-linux-test/bin"
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/sh' \
  '[ "$1" = --version ] && { echo v9.9.9; exit 0; }' \
  'exec /bin/sh "$@"' > "${fake_node_root}/node-v9.9.9-linux-test/bin/node"
chmod 0755 "${fake_node_root}/node-v9.9.9-linux-test/bin/node"
printf '%s\n' 'MIT' > "${fake_node_root}/node-v9.9.9-linux-test/LICENSE"

fake_codex_root="${TEST_TMP}/codex-root"
mkdir -p "${fake_codex_root}"
printf '%s\n' '#!/bin/sh' 'echo "codex-cli 9.9.9"' \
  > "${fake_codex_root}/codex-x86_64-unknown-linux-musl"
chmod 0755 "${fake_codex_root}/codex-x86_64-unknown-linux-musl"

fake_acp_root="${TEST_TMP}/acp-root"
mkdir -p "${fake_acp_root}/package/dist"
# shellcheck disable=SC2016
printf '%s\n' \
  'if [ "$1" = --version ]; then echo "@agentclientprotocol/codex-acp 9.9.9"; exit 0; fi' \
  'echo "CODEX_PATH=${CODEX_PATH}"' > "${fake_acp_root}/package/dist/index.js"
printf '%s\n' 'Apache-2.0' > "${fake_acp_root}/package/LICENSE"

# A buildpack directory whose manifest pins the given archive roots, bundled the
# way the cached release bundles the real archives.
fake_buildpack() {
  local bp_dir=$1 node_root=$2 codex_root=$3 acp_root=$4
  local dependency root
  local shas=()

  mkdir -p "${bp_dir}/config" "${bp_dir}/dependencies" "${bp_dir}/lib"
  cp "${repo_dir}/lib/codex-acp-wrapper.sh" "${bp_dir}/lib/"
  for dependency in node codex codex-acp; do
    case "${dependency}" in
      node) root=${node_root} ;;
      codex) root=${codex_root} ;;
      codex-acp) root=${acp_root} ;;
    esac
    (cd "${root}" && tar czf "${bp_dir}/dependencies/${dependency}-test.tar.gz" -- *)
    shas+=("$(sha256_file "${bp_dir}/dependencies/${dependency}-test.tar.gz")")
  done
  jq -n --arg node "${shas[0]}" --arg codex "${shas[1]}" --arg acp "${shas[2]}" '
    def pinned($name; $sha): {
      version: "9.9.9",
      assets: {
        amd64: {filename: ($name + "-test.tar.gz"), url: "https://example.com/unused", sha256: $sha},
        arm64: {filename: ($name + "-test.tar.gz"), url: "https://example.com/unused", sha256: $sha}
      }
    };
    {
      schemaVersion: 1,
      dependencies: {
        node: pinned("node"; $node),
        codex: pinned("codex"; $codex),
        "codex-acp": pinned("codex-acp"; $acp)
      }
    }' > "${bp_dir}/config/dependencies.json"
}

install_all() {
  local install_dir=$1 bp_dir=$2
  install_node "${install_dir}" "${TEST_TMP}/cache" "${bp_dir}" \
    && install_codex "${install_dir}" "${TEST_TMP}/cache" "${bp_dir}" \
    && install_codex_acp "${install_dir}" "${TEST_TMP}/cache" "${bp_dir}"
}

fake_buildpack "${TEST_TMP}/bp" "${fake_node_root}" "${fake_codex_root}" "${fake_acp_root}"

install_dir="${TEST_TMP}/deps/0"
install_all "${install_dir}" "${TEST_TMP}/bp" >/dev/null
assert_eq "v9.9.9" "$("${install_dir}/node/bin/node" --version)"
assert_eq "codex-cli 9.9.9" "$("${install_dir}/bin/codex" --version)"
assert_eq "@agentclientprotocol/codex-acp 9.9.9" "$("${install_dir}/bin/codex-acp" --version)"
assert_eq "9.9.9" "${CODEX_RESOLVED_VERSION}"
assert_eq "9.9.9" "${CODEX_ACP_RESOLVED_VERSION}"
[ -f "${install_dir}/node/LICENSE" ] || fail "Node.js licence was not installed"
[ -f "${install_dir}/codex-acp/LICENSE" ] || fail "codex-acp licence was not installed"
[ ! -e "${install_dir}/bin/node" ] || fail "node must stay off PATH"
verify_installation "${install_dir}" >/dev/null || fail "installation did not verify"

# The wrapper points codex-acp at the codex beside it, unless told otherwise.
assert_eq "CODEX_PATH=${install_dir}/bin/codex" \
  "$(env -u CODEX_PATH "${install_dir}/bin/codex-acp")"
assert_eq "CODEX_PATH=/opt/codex" "$(CODEX_PATH=/opt/codex "${install_dir}/bin/codex-acp")"

# A codex outside the manifest needs its own URL and checksum.
if CODEX_VERSION=1.0.0 install_codex "${TEST_TMP}/deps/1" "${TEST_TMP}/cache" \
    "${TEST_TMP}/bp" >/dev/null 2>&1; then
  fail "unpinned CODEX_VERSION was installed without a checksum"
fi
if CODEX_ACP_VERSION=1.0.0 CODEX_ACP_DOWNLOAD_URL=http://example.com/acp.tgz \
    CODEX_ACP_SHA256="$(sha256_file "${TEST_TMP}/bp/dependencies/codex-acp-test.tar.gz")" \
    install_codex_acp "${TEST_TMP}/deps/1" "${TEST_TMP}/cache" "${TEST_TMP}/bp" \
    >/dev/null 2>&1; then
  fail "custom codex-acp was accepted over plain HTTP"
fi

# A bundled archive that does not match its pin is refused.
cp -R "${TEST_TMP}/bp" "${TEST_TMP}/tampered-bp"
printf '%s' 'tampered' >> "${TEST_TMP}/tampered-bp/dependencies/codex-test.tar.gz"
if install_codex "${TEST_TMP}/deps/2" "${TEST_TMP}/cache" "${TEST_TMP}/tampered-bp" \
    >/dev/null 2>&1; then
  fail "tampered codex archive was installed"
fi

# So is a correctly pinned codex archive with anything more than the binary.
crowded_codex="${TEST_TMP}/crowded-codex"
cp -R "${fake_codex_root}" "${crowded_codex}"
cp "${crowded_codex}/codex-x86_64-unknown-linux-musl" "${crowded_codex}/codex-aarch64-unknown-linux-musl"
fake_buildpack "${TEST_TMP}/crowded-bp" "${fake_node_root}" "${crowded_codex}" "${fake_acp_root}"
if install_codex "${TEST_TMP}/deps/3" "${TEST_TMP}/cache" "${TEST_TMP}/crowded-bp" \
    >/dev/null 2>&1; then
  fail "codex archive with unexpected contents was installed"
fi

# And a codex-acp package without its script.
hollow_acp="${TEST_TMP}/hollow-acp"
mkdir -p "${hollow_acp}/package"
cp "${fake_acp_root}/package/LICENSE" "${hollow_acp}/package/"
fake_buildpack "${TEST_TMP}/hollow-bp" "${fake_node_root}" "${fake_codex_root}" "${hollow_acp}"
if install_codex_acp "${TEST_TMP}/deps/4" "${TEST_TMP}/cache" "${TEST_TMP}/hollow-bp" \
    >/dev/null 2>&1; then
  fail "codex-acp archive without dist/index.js was installed"
fi

echo "install-test: PASS"
