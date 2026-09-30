#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "${repo_dir}/tests/test-helper.sh"
source "${repo_dir}/lib/installer.sh"

printf '%s' 'pinned' > "${TEST_TMP}/pinned"
expected=$(sha256_file "${TEST_TMP}/pinned")
verify_sha256 "${TEST_TMP}/pinned" "${expected}" >/dev/null \
  || fail "matching checksum was rejected"
printf '%s' 'tampered' > "${TEST_TMP}/tampered"
if verify_sha256 "${TEST_TMP}/tampered" "${expected}" >/dev/null 2>&1; then
  fail "tampered dependency passed verification"
fi
if verify_sha256 "${TEST_TMP}/pinned" "not-a-sha" >/dev/null 2>&1; then
  fail "malformed expected checksum was accepted"
fi
if download_atomic "http://example.com/codex" "${TEST_TMP}/codex" "${expected}" \
    >/dev/null 2>&1; then
  fail "non-HTTPS download was attempted"
fi

for arch in amd64 arm64; do
  assert_eq "jq-linux-${arch}" "$(bootstrap_jq_metadata "${arch}" | cut -f1)"
done
if bootstrap_jq_metadata riscv64 >/dev/null; then
  fail "unsupported architecture has jq metadata"
fi

echo "dependency-test: PASS"
