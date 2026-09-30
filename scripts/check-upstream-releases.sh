#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
manifest="${repo_dir}/config/dependencies.json"
fail_on_update=false
[ "${1:-}" = "--fail-on-update" ] && fail_on_update=true

fetch() {
  curl --fail --silent --show-error --location \
    --connect-timeout 15 --max-time 60 "$@"
}

github_api() {
  local path=$1
  local args=(-H "Accept: application/vnd.github+json")
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  fetch "${args[@]}" "https://api.github.com/${path}"
}

pinned_value() {
  jq -r --arg dependency "$1" ".dependencies[\$dependency].$2" "${manifest}"
}

updates=0
report() {
  local dependency=$1 pinned=$2 latest=$3
  if [ "${pinned}" = "${latest}" ]; then
    echo "${dependency}: current (${pinned})"
  elif [ "$(pinned_value "${dependency}" failOnUpdate)" = true ]; then
    echo "${dependency}: update available (${pinned} -> ${latest})"
    updates=$((updates + 1))
  else
    echo "${dependency}: update available (${pinned} -> ${latest}) [non-blocking]"
  fi
}

# Dependency, GitHub repository, and the prefix its release tags carry.
releases=$(cat <<'EOF'
codex-acp	agentclientprotocol/codex-acp	v
codex	openai/codex	rust-v
jq	jqlang/jq	jq-
node	nodejs/node	v
EOF
)

while IFS=$'\t' read -r dependency repository prefix; do
  [ "${dependency}" = node ] && continue
  latest_tag=$(github_api "repos/${repository}/releases/latest" | jq -er '.tag_name')
  report "${dependency}" "$(pinned_value "${dependency}" version)" "${latest_tag#"${prefix}"}"
done <<< "${releases}"

# Node.js is pinned to an LTS line, so compare with that line's latest release,
# not with the newest Current release.
pinned_node=$(pinned_value node version)
latest_node=$(fetch https://nodejs.org/dist/index.json \
  | jq -er --arg major "v${pinned_node%%.*}." \
    '[.[] | select(.version | startswith($major))][0].version')
report node "${pinned_node}" "${latest_node#v}"

# codex-acp names the @openai/codex it was built against; the pinned codex must
# be the one recorded for it.
pinned_acp=$(pinned_value codex-acp version)
published_range=$(fetch \
  "https://registry.npmjs.org/@agentclientprotocol/codex-acp/${pinned_acp}" \
  | jq -er '.dependencies["@openai/codex"]')
[ "${published_range}" = "$(pinned_value codex-acp codexRange)" ] || {
  echo "codex-acp ${pinned_acp} requires @openai/codex ${published_range}, not the recorded codexRange" >&2
  exit 1
}
echo "codex-acp: requires @openai/codex ${published_range}, as recorded"

while IFS=$'\t' read -r dependency repository prefix; do
  pinned_commit=$(pinned_value "${dependency}" sourceCommit)
  [ "${pinned_commit}" = null ] && continue
  tag="${prefix}$(pinned_value "${dependency}" version)"
  tag_object=$(github_api "repos/${repository}/git/ref/tags/${tag}")
  tag_type=$(jq -r '.object.type' <<< "${tag_object}")
  tag_sha=$(jq -r '.object.sha' <<< "${tag_object}")
  if [ "${tag_type}" = "tag" ]; then
    tag_sha=$(github_api "repos/${repository}/git/tags/${tag_sha}" \
      | jq -er '.object.sha')
  fi
  [ "${tag_sha}" = "${pinned_commit}" ] || {
    echo "Pinned ${dependency} source commit does not match tag ${tag}" >&2
    exit 1
  }
  echo "${dependency}: tag ${tag} matches pinned source commit"
done <<< "${releases}"

if [ "${updates}" -gt 0 ] && [ "${fail_on_update}" = true ]; then
  echo "${updates} pinned dependency update(s) require review" >&2
  exit 1
fi
