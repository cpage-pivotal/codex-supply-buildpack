# Codex Supply Buildpack

A Cloud Foundry v2 **supply buildpack** that puts a checksum-verified
[codex-acp](https://github.com/agentclientprotocol/codex-acp) and
[Codex](https://github.com/openai/codex), with Codex's code-mode host, in the
droplet, and exports `CODEX_ACP_CLI_PATH` and `CODEX_PATH`. That is everything
it does.

It is for applications built on [Spring AI ACP](https://github.com/cpage-pivotal/acp-spring),
such as `spring-ai-acp-chat`. Codex has no ACP mode of its own. Spring AI ACP's
Codex runtime adapter launches codex-acp, the ACP adapter for Codex, from the
path in `CODEX_ACP_CLI_PATH` (otherwise it would fetch codex-acp with `npx`). codex-acp in turn runs
`$CODEX_PATH app-server`. Spring AI ACP configures the agent itself: provider
and model (including from a bound Tanzu AI Models service), MCP servers,
skills, and the `config.toml` it writes under `CODEX_HOME`. This buildpack
therefore writes no Codex configuration and reads no service bindings.

- Buildpack: **1.0.0**
- codex-acp: **2.1.1**
- Codex: **0.159.3**, and its code-mode host from the same release
- Node.js: **24.21.0** (LTS, runs codex-acp)
- Architectures: Linux amd64 and arm64

## Usage

Name it before the final buildpack. A supply buildpack is never auto-detected.

```yaml
applications:
  - name: spring-ai-acp-chat
    path: target/spring-ai-acp-chat-1.0.0.jar
    buildpacks:
      - https://github.com/cpage-pivotal/codex-supply-buildpack
      - java_buildpack_offline
    env:
      ACP_RUNTIME: codex
```

At startup, `.profile.d/codex-env.sh` sets:

| Variable | Value |
| --- | --- |
| `CODEX_ACP_CLI_PATH` | `$DEPS_DIR/<index>/bin/codex-acp` |
| `CODEX_PATH` | `$DEPS_DIR/<index>/bin/codex`, the binary codex-acp runs |
| `PATH` | `$DEPS_DIR/<index>/bin` prepended (codex-acp, codex and jq) |

Spring AI ACP reads `CODEX_ACP_CLI_PATH` from 0.3.1. On an earlier version,
point it at the adapter explicitly:

```yaml
spring:
  acp:
    runtimes:
      codex:
        command: ${CODEX_ACP_CLI_PATH}
```

## What staging does

1. Installs jq, pinned by SHA-256 in `lib/installer.sh`, to read the dependency
   manifest.
2. Installs Node.js, codex, its code-mode host and codex-acp for the
   container's architecture from
   `config/dependencies.json`. Every download is HTTPS only and SHA-256
   verified, and no archive may contain absolute or `..` paths.
   - **Node.js:** only `bin/node` and its licence are taken from the release,
     into `$DEPS_DIR/<index>/node`. It is kept off `PATH`, so it never shadows
     a Node.js the application or another buildpack supplies.
   - **Codex:** the archive must hold exactly one `codex-<triple>` binary,
     which is installed as `bin/codex`.
   - **Code-mode host:** the archive must hold exactly one
     `codex-code-mode-host-<triple>` binary, which is installed as
     `bin/codex-code-mode-host`, where Codex looks for it. It must be the same
     version as Codex.
   - **codex-acp:** only `package/dist/index.js`, a single self-contained
     script, and its licence are taken from the npm package. `bin/codex-acp`
     runs it on the pinned Node.js. `CODEX_PATH` defaults to the `codex` beside
     it.
3. Writes the profile script and `<deps>/<index>/config.yml`, then runs each
   executable's `--version`.

Archives are taken from the buildpack's own `dependencies/` directory (the
cached release), then the staging cache, then downloaded.

The pinned Codex assets are upstream's static musl builds, which suit
cflinuxfs4. They add about 280 MB to the droplet, the code-mode host about
75 MB, and Node.js about 120 MB.

### Code mode

Codex's current models (all but `gpt-5.5` in Codex 0.159.1's catalog) call
every tool, MCP servers included, from JavaScript run by
`codex-code-mode-host`, a separate binary in Codex's release. Codex looks for
it beside its own executable. Without it those models are left with no tools
at all: Codex warns "Code Mode is unavailable ... Code mode will fail closed",
and the agent answers as if its MCP servers were down. That is why the host is
installed, not optional.

### Sandboxing

On Linux, Codex's filesystem sandbox runs commands under bubblewrap, which
needs unprivileged user namespaces. This buildpack ships no `bwrap`, and a
Cloud Foundry app container may not allow those namespaces. In that case Codex
warns at startup, and the sandboxed approval modes can't run shell commands.
Use the full-access mode and let the container be the isolation boundary.

### A Codex or codex-acp that is not pinned

To stage a version the manifest doesn't pin, set all three variables for that
dependency:

```yaml
env:
  CODEX_VERSION: 0.159.2
  CODEX_DOWNLOAD_URL: https://github.com/openai/codex/releases/download/rust-v0.159.2/codex-x86_64-unknown-linux-musl.tar.gz
  CODEX_SHA256: <64 hex characters>
```

`CODEX_ACP_VERSION`, `CODEX_ACP_DOWNLOAD_URL` and `CODEX_ACP_SHA256` do the
same for codex-acp's npm tarball. The code-mode host must match Codex, so a
Codex override needs `CODEX_CODE_MODE_HOST_VERSION`,
`CODEX_CODE_MODE_HOST_DOWNLOAD_URL` and `CODEX_CODE_MODE_HOST_SHA256` for the
same release; staging fails if the two versions differ. An override applies only when its `_VERSION`
(ignoring a leading `v`) differs from the pinned version. If it matches, the
pinned asset is installed and the other two variables are ignored. codex-acp
drives Codex over its app-server protocol, so keep the two compatible. Each
codex-acp release names the `@openai/codex` it was built against.

## Releases

Pushing a `v*` tag builds an offline (cached) buildpack per architecture with
all five dependencies bundled, plus a CycloneDX SBOM and checksums:

```bash
cf create-buildpack codex_supply_buildpack codex_supply_buildpack-cached-v1.0.0-amd64.zip 99
```

## Development

```bash
make test        # bash -n, shellcheck, dependency metadata, tests/*-test.sh
make package     # online zip + validated SBOM in build/
make freshness   # compare pins with the latest upstream releases
```

codex-acp and Codex move together:

1. Read the new codex-acp's `@openai/codex` range
   (`npm view @agentclientprotocol/codex-acp@X.Y.Z dependencies`).
2. Set it as `codexRange` in `config/dependencies.json`.
3. Pin a Codex release that satisfies it. `make dependencies` fails if the
   pinned Codex falls outside the range, and `make freshness` fails if
   `codexRange` differs from what npm publishes.
4. Pin `codex-code-mode-host` to the same release: the same `version`,
   `sourceCommit` and tag in `purl`, and its own assets' URLs and SHA-256s.
   `make dependencies` fails if it differs from Codex.

For each dependency, update `version`, `sourceCommit`, `purl`, and both
assets' URL and SHA-256. Also update the versions in this README and
SECURITY.md. Where to get the SHA-256s:

| Dependency | Source |
| --- | --- |
| Codex and its code-mode host | the release's asset digests (`gh release view rust-vX.Y.Z --repo openai/codex --json assets`) |
| Node.js | `https://nodejs.org/dist/vX.Y.Z/SHASUMS256.txt` |
| codex-acp | the downloaded tarball |

To bump jq, change it in both `config/dependencies.json` and
`bootstrap_jq_metadata` in `lib/installer.sh`. `make dependencies` fails if
they differ.
