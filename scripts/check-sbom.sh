#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
sbom=${1:-"${repo_dir}/build/codex-supply-buildpack.cdx.json"}
manifest="${repo_dir}/config/dependencies.json"

[ -f "${sbom}" ] || {
  echo "SBOM not found: ${sbom}" >&2
  exit 1
}

jq -e '
  .bomFormat == "CycloneDX"
  and .specVersion == "1.5"
  and (.metadata.component.name == "codex-supply-buildpack")
  and (.components | type == "array")
' "${sbom}" >/dev/null

expected_count=$(jq '.dependencies | length' "${manifest}")
actual_count=$(jq '.components | length' "${sbom}")
[ "${actual_count}" -eq "${expected_count}" ] || {
  echo "SBOM component count does not match dependency manifest" >&2
  exit 1
}

while IFS= read -r dependency; do
  expected_version=$(jq -r --arg dependency "${dependency}" \
    '.dependencies[$dependency].version' "${manifest}")
  expected_purl=$(jq -r --arg dependency "${dependency}" \
    '.dependencies[$dependency].purl' "${manifest}")
  expected_license=$(jq -r --arg dependency "${dependency}" \
    '.dependencies[$dependency].license' "${manifest}")

  jq -e \
    --arg dependency "${dependency}" \
    --arg version "${expected_version}" \
    --arg purl "${expected_purl}" \
    --arg license "${expected_license}" '
      any(.components[];
        .name == $dependency
        and .version == $version
        and .purl == $purl
        and any(.licenses[]?; .license.name == $license)
      )
    ' "${sbom}" >/dev/null || {
      echo "SBOM metadata mismatch for ${dependency}" >&2
      exit 1
    }

  while IFS=$'\t' read -r architecture sha256; do
    jq -e \
      --arg dependency "${dependency}" \
      --arg property "codex-supply-buildpack:asset-sha256:${architecture}" \
      --arg sha256 "${sha256}" '
        any(.components[];
          .name == $dependency
          and any(.properties[]?;
            .name == $property and .value == $sha256
          )
        )
      ' "${sbom}" >/dev/null || {
        echo "SBOM checksum mismatch for ${dependency}/${architecture}" >&2
        exit 1
      }
  done < <(jq -r --arg dependency "${dependency}" \
    '.dependencies[$dependency].assets
      | to_entries[]
      | [.key, .value.sha256]
      | @tsv' "${manifest}")
done < <(jq -r '.dependencies | keys[]' "${manifest}")

while IFS=$'\t' read -r dependency commit; do
  jq -e --arg dependency "${dependency}" --arg commit "${commit}" '
    any(.components[];
      .name == $dependency
      and any(.externalReferences[]?;
        .type == "vcs" and (.url | endswith("#" + $commit))
      )
    )
  ' "${sbom}" >/dev/null || {
    echo "SBOM is missing the pinned source commit for ${dependency}" >&2
    exit 1
  }
done < <(jq -r '.dependencies
  | to_entries[]
  | select(.value.sourceCommit)
  | [.key, .value.sourceCommit]
  | @tsv' "${manifest}")

echo "CycloneDX SBOM matches the dependency manifest"
