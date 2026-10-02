# Security policy

## Supported versions

Security fixes go into the latest minor release of this buildpack and the
dependency versions it pins.

| Component | Supported |
| --- | --- |
| Buildpack 1.0.x | Yes |
| codex-acp 2.1.x, Codex 0.159.x (with its code-mode host) and Node.js 24.x bundled here | Yes |
| Earlier versions | No |

## Reporting a vulnerability

Don't open a public issue with exploit details, credentials, internal routes or
customer information. Use GitHub's private security-advisory reporting for this
repository. If that isn't enabled, contact the maintainers privately and ask for
a secure channel.

Include the affected version, the impact, a minimal reproduction, and whether the
issue is in this buildpack or upstream (codex-acp, Codex or Node.js).

## Security posture

- Dependencies are fetched over HTTPS only and pinned by SHA-256, both when
  downloaded and when taken from the cache or a cached release.
- `config/dependencies.json` records a security floor for Codex (0.39.0, which
  fixes GHSA-w5fx-fh39-j5rw and GHSA-xrxf-jgv3-qmrm) and the advisories it
  fixes. `make dependencies` fails if the pinned Codex is below that floor, or
  outside the `@openai/codex` range the pinned codex-acp was built against.
- Archives are refused if they contain absolute or parent-directory paths.
  Staging extracts only named members:
  - the single `codex-<triple>` binary from Codex's archive
  - the single `codex-code-mode-host-<triple>` binary from its archive, which
    must come from the same Codex release as `codex`
  - `bin/node` and `LICENSE` from Node.js
  - `package/dist/index.js` and `package/LICENSE` from codex-acp
- Node.js stays off `PATH`. Only the `codex-acp` wrapper runs it.
- Codex's bubblewrap sandbox may be unavailable in a Cloud Foundry container
  (see the README). Treat the container as the isolation boundary.
- Cached releases are per-architecture and ship with a CycloneDX SBOM.
- The buildpack reads no service bindings and writes no credentials into the
  droplet.

### Upstream Codex dependencies

CI audits `codex-rs/Cargo.lock` at the pinned Codex source commit with
`cargo audit` and uploads the JSON report, but a finding does not fail the
build. The lockfile covers the whole Codex workspace, not just the `codex`
and `codex-code-mode-host` binaries. At Codex 0.159.1, OSV reported open advisories against 19 of its
1,297 crates, among them `openssl` 0.10.75, `gix` 0.81.0, `hickory-proto`
0.25.2 and `quick-xml` 0.39.4. It flagged 6 more crates as unmaintained.
Only an upstream release can fix these, and a reviewed ignore list of that size
would hide new findings rather than surface them. Review the report when you
bump Codex, and prefer a Codex release that clears them.

### Upstream codex-acp dependencies

codex-acp is published as a single bundled script, so its npm dependency tree
isn't audited here. The buildpack relies on the pinned version, codex-acp's own
advisories, and the weekly upstream release watch, which fails on any new
codex-acp or Node.js 24 release.
