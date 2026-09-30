#!/usr/bin/env bash
# The runtime environment: where codex-acp and the codex it runs are.

setup_environment() {
    local deps_dir=$1
    local build_dir=$2
    local index=$3
    local profile_script="${build_dir}/.profile.d/codex-env.sh"

    mkdir -p "${build_dir}/.profile.d"
    {
        printf '%s\n' '# Codex supply buildpack runtime environment'
        # These variables intentionally expand when Cloud Foundry sources the profile.
        # shellcheck disable=SC2016
        printf 'export PATH="$DEPS_DIR/%s/bin:$PATH"\n' "${index}"
        # shellcheck disable=SC2016
        printf 'export CODEX_ACP_CLI_PATH="$DEPS_DIR/%s/bin/codex-acp"\n' "${index}"
        # shellcheck disable=SC2016
        printf 'export CODEX_PATH="$DEPS_DIR/%s/bin/codex"\n' "${index}"
    } > "${profile_script}"
    chmod 0644 "${profile_script}"

    export PATH="${deps_dir}/bin:${PATH}"
    export CODEX_ACP_CLI_PATH="${deps_dir}/bin/codex-acp"
    export CODEX_PATH="${deps_dir}/bin/codex"
}

# The multi-buildpack convention: a supply buildpack describes what it supplied
# in <deps>/<index>/config.yml for the buildpacks that follow it.
create_config_file() {
    local deps_dir=$1
    local bp_dir=$2
    local config_file="${deps_dir}/config.yml"
    local manifest="${bp_dir}/config/dependencies.json"
    local version="${CODEX_ACP_RESOLVED_VERSION:-$(dependency_version "${manifest}" codex-acp)}"
    local codex_version="${CODEX_RESOLVED_VERSION:-$(dependency_version "${manifest}" codex)}"

    cat > "${config_file}" <<CONFIG
---
name: codex-supply-buildpack
config:
  version: ${version}
  codex_version: ${codex_version}
  cli_path: ${deps_dir}/bin/codex-acp
  codex_path: ${deps_dir}/bin/codex
CONFIG
    chmod 0644 "${config_file}"
}
