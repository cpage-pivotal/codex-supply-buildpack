#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output=${1:-"${repo_dir}/build/codex-supply-buildpack.cdx.json"}
mkdir -p "$(dirname "${output}")"

jq -n \
  --arg version "$(tr -d '[:space:]' < "${repo_dir}/VERSION")" \
  --slurpfile manifest "${repo_dir}/config/dependencies.json" '
  {
    bomFormat: "CycloneDX",
    specVersion: "1.5",
    version: 1,
    metadata: {
      component: {
        type: "application",
        name: "codex-supply-buildpack",
        version: $version,
        purl: ("pkg:github/cpage-pivotal/codex-supply-buildpack@" + $version)
      }
    },
    components: (
      [
        $manifest[0].dependencies
        | to_entries[]
        | {
            type: "application",
            name: .key,
            version: .value.version,
            purl: .value.purl,
            licenses: [{license: {name: .value.license}}],
            externalReferences: (
              [{type: "website", url: .value.source}]
              + if .value.sourceCommit then
                  [{
                    type: "vcs",
                    url: (.value.source + "#"
                      + .value.sourceCommit)
                  }]
                else [] end
            ),
            properties: ([
              .value.assets | to_entries[] | {
                name: ("codex-supply-buildpack:asset-sha256:" + .key),
                value: .value.sha256
              }
            ] + [
              .value.security.fixedAdvisories[]? | {
                name: "codex-supply-buildpack:fixed-advisory",
                value: (.id + " (" + .affectedVersions + ")")
              }
            ])
          }
      ]
    )
  }
' > "${output}"

echo "${output}"
