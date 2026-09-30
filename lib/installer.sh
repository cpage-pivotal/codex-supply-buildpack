#!/usr/bin/env bash
# Dependency installation with publisher-pinned SHA-256 verification.

host_architecture() {
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *)
            echo "       ERROR: Unsupported architecture: $(uname -m)" >&2
            return 1
            ;;
    esac
}

sha256_file() {
    local file=$1
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${file}" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${file}" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "${file}" | awk '{print $NF}'
    else
        echo "       ERROR: sha256sum, shasum, or openssl is required" >&2
        return 1
    fi
}

verify_sha256() {
    local file=$1
    local expected=$2
    local actual

    [ -f "${file}" ] || {
        echo "       ERROR: Dependency not found: ${file}" >&2
        return 1
    }
    [[ "${expected}" =~ ^[a-f0-9]{64}$ ]] || {
        echo "       ERROR: Invalid expected SHA-256 for $(basename "${file}")" >&2
        return 1
    }
    actual=$(sha256_file "${file}") || return 1
    if [ "${actual}" != "${expected}" ]; then
        echo "       ERROR: SHA-256 mismatch for $(basename "${file}")" >&2
        echo "       Expected: ${expected}" >&2
        echo "       Actual:   ${actual}" >&2
        return 1
    fi
    echo "       Verified SHA-256 for $(basename "${file}")"
}

download_atomic() {
    local url=$1
    local destination=$2
    local expected_sha=$3
    local partial="${destination}.part"
    local retry_count=0

    [[ "${url}" == https://* ]] || {
        echo "       ERROR: Refusing non-HTTPS dependency URL" >&2
        return 1
    }
    rm -f "${partial}"
    while [ "${retry_count}" -lt 3 ]; do
        if curl --fail --silent --show-error --location \
            --connect-timeout 15 --max-time 300 \
            "${url}" --output "${partial}"; then
            if verify_sha256 "${partial}" "${expected_sha}"; then
                mv "${partial}" "${destination}"
                return 0
            fi
            rm -f "${partial}"
            return 1
        fi
        retry_count=$((retry_count + 1))
        echo "       Download failed; retry ${retry_count}/3" >&2
    done
    rm -f "${partial}"
    echo "       ERROR: Failed to download ${url}" >&2
    return 1
}

# jq reads config/dependencies.json, so its own pin cannot live there alone:
# scripts/check-dependencies.sh fails if this copy drifts from the manifest.
bootstrap_jq_metadata() {
    local arch=$1
    case "${arch}" in
        amd64)
            printf '%s\t%s\t%s\n' \
                "jq-linux-amd64" \
                "https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-amd64" \
                "b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f"
            ;;
        arm64)
            printf '%s\t%s\t%s\n' \
                "jq-linux-arm64" \
                "https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-arm64" \
                "8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309"
            ;;
        *) return 1 ;;
    esac
}

install_jq() {
    local install_dir=$1
    local bp_dir=$2
    local cache_dir=$3
    local arch filename url expected src dst cache_file

    arch=$(host_architecture) || return 1
    mkdir -p "${install_dir}/bin" "${cache_dir}"

    IFS=$'\t' read -r filename url expected < <(bootstrap_jq_metadata "${arch}")
    src="${bp_dir}/dependencies/${filename}"
    cache_file="${cache_dir}/${filename}"
    dst="${install_dir}/bin/jq"

    if [ -f "${src}" ]; then
        verify_sha256 "${src}" "${expected}" || return 1
        cp "${src}" "${dst}"
    elif [ -f "${cache_file}" ]; then
        verify_sha256 "${cache_file}" "${expected}" || return 1
        cp "${cache_file}" "${dst}"
    else
        echo "       Downloading jq for ${arch}"
        download_atomic "${url}" "${cache_file}" "${expected}" || return 1
        cp "${cache_file}" "${dst}"
    fi
    chmod 0755 "${dst}"

    export PATH="${install_dir}/bin:${PATH}"
    "${dst}" --version >/dev/null
    echo "       Installed verified jq for ${arch}"
}

dependency_value() {
    local manifest=$1
    local dependency=$2
    local arch=$3
    local field=$4
    jq -er --arg dependency "${dependency}" --arg arch "${arch}" --arg field "${field}" \
        '.dependencies[$dependency].assets[$arch][$field]' "${manifest}"
}

dependency_version() {
    local manifest=$1
    local dependency=$2
    jq -er --arg dependency "${dependency}" '.dependencies[$dependency].version' "${manifest}"
}

# Finds a dependency's archive and checks it against its pin. The archive comes
# from the buildpack's own dependencies/ directory (the cached release), then
# the staging cache, then a download. With an env prefix, <PREFIX>_VERSION
# names a build the manifest doesn't pin, but only if <PREFIX>_DOWNLOAD_URL
# and <PREFIX>_SHA256 are set too. Sets FETCHED_ARCHIVE and FETCHED_VERSION.
fetch_verified() {
    local dependency=$1
    local arch=$2
    local cache_dir=$3
    local bp_dir=$4
    local env_prefix=${5:-}
    local manifest="${bp_dir}/config/dependencies.json"
    local version filename url expected custom_version custom_url custom_sha
    local version_var url_var sha_var cache_file bundled_archive

    [ -f "${manifest}" ] || {
        echo "       ERROR: Dependency manifest not found: ${manifest}" >&2
        return 1
    }
    jq -e '.schemaVersion == 1' "${manifest}" >/dev/null || {
        echo "       ERROR: Unsupported dependency manifest" >&2
        return 1
    }

    version=$(dependency_version "${manifest}" "${dependency}") || return 1
    filename=$(dependency_value "${manifest}" "${dependency}" "${arch}" filename) || return 1
    url=$(dependency_value "${manifest}" "${dependency}" "${arch}" url) || return 1
    expected=$(dependency_value "${manifest}" "${dependency}" "${arch}" sha256) || return 1

    if [ -n "${env_prefix}" ]; then
        version_var="${env_prefix}_VERSION"
        url_var="${env_prefix}_DOWNLOAD_URL"
        sha_var="${env_prefix}_SHA256"
        custom_version="${!version_var:-}"
        custom_url="${!url_var:-}"
        custom_sha="${!sha_var:-}"
    else
        custom_version=""
    fi

    if [ -n "${custom_version}" ] && [ "${custom_version#v}" != "${version}" ]; then
        if [ -z "${custom_url}" ] || [ -z "${custom_sha}" ]; then
            echo "       ERROR: ${version_var}=${custom_version} is not in the dependency manifest" >&2
            echo "       Supply both ${url_var} and ${sha_var} for an explicit custom build" >&2
            return 1
        fi
        [[ "${custom_url}" == https://* ]] || {
            echo "       ERROR: ${url_var} must use HTTPS" >&2
            return 1
        }
        version="${custom_version#v}"
        filename="${dependency}-custom-${arch}.tar.gz"
        url="${custom_url}"
        expected="${custom_sha}"
        echo "       Using explicitly checksummed custom ${dependency} ${version}"
    else
        echo "       Using manifest-pinned ${dependency} ${version} for ${arch}"
    fi

    cache_file="${cache_dir}/${dependency}-${version}-${arch}.tar.gz"
    bundled_archive="${bp_dir}/dependencies/${filename}"
    mkdir -p "${cache_dir}"

    if [ -f "${bundled_archive}" ]; then
        verify_sha256 "${bundled_archive}" "${expected}" || return 1
        FETCHED_ARCHIVE="${bundled_archive}"
        echo "       Using verified bundled ${dependency} archive"
    elif [ -f "${cache_file}" ]; then
        verify_sha256 "${cache_file}" "${expected}" || return 1
        FETCHED_ARCHIVE="${cache_file}"
        echo "       Using verified cached ${dependency} archive"
    else
        echo "       Downloading ${dependency} ${version}"
        download_atomic "${url}" "${cache_file}" "${expected}" || return 1
        FETCHED_ARCHIVE="${cache_file}"
    fi
    FETCHED_VERSION="${version}"
}

# Prints a .tar.gz's members, failing if any is absolute or climbs out with "..".
archive_members() {
    local archive=$1
    tar tzf "${archive}" | awk '
        /^\// || /(^|\/)\.\.(\/|$)/ { unsafe = 1 }
        { print }
        END { exit unsafe }
    '
}

# Node.js runs codex-acp. Only the node binary and its licence are taken from
# the release, and they stay off PATH so they never shadow an application's own
# Node.js.
install_node() {
    local install_dir=$1
    local cache_dir=$2
    local bp_dir=$3
    local arch members member top

    arch=$(host_architecture) || return 1
    fetch_verified node "${arch}" "${cache_dir}" "${bp_dir}" || return 1

    if ! members=$(archive_members "${FETCHED_ARCHIVE}") \
        || ! member=$(awk '/^[^\/]+\/bin\/node$/ { n++; m = $0 }
            END { if (n == 1) print m; exit n != 1 }' <<< "${members}"); then
        echo "       ERROR: Node.js archive has unexpected or unsafe contents" >&2
        return 1
    fi
    top=${member%%/*}

    rm -rf "${install_dir}/node"
    mkdir -p "${install_dir}/node"
    tar xzf "${FETCHED_ARCHIVE}" -C "${install_dir}/node" --strip-components=1 \
        "${member}" "${top}/LICENSE"
    chmod 0755 "${install_dir}/node/bin/node"

    if ! "${install_dir}/node/bin/node" --version >/dev/null 2>&1; then
        echo "       ERROR: Node.js failed its version check" >&2
        return 1
    fi
    echo "       Installed Node.js $("${install_dir}/node/bin/node" --version)"
}

# The native codex, which codex-acp runs as `codex app-server`. Upstream's
# archive holds a single binary named for its target triple.
install_codex() {
    local install_dir=$1
    local cache_dir=$2
    local bp_dir=$3
    local arch members member

    arch=$(host_architecture) || return 1
    fetch_verified codex "${arch}" "${cache_dir}" "${bp_dir}" CODEX || return 1

    if ! members=$(archive_members "${FETCHED_ARCHIVE}") \
        || ! member=$(awk 'NR == 1 && /^codex-[a-z0-9_]+-unknown-linux-musl$/ { m = $0 }
            END { if (NR == 1 && m != "") print m; exit !(NR == 1 && m != "") }' \
            <<< "${members}"); then
        echo "       ERROR: Codex archive has unexpected or unsafe contents" >&2
        return 1
    fi

    mkdir -p "${install_dir}/bin"
    tar xzf "${FETCHED_ARCHIVE}" -C "${install_dir}/bin" "${member}"
    mv -f "${install_dir}/bin/${member}" "${install_dir}/bin/codex"
    chmod 0755 "${install_dir}/bin/codex"

    if ! "${install_dir}/bin/codex" --version >/dev/null 2>&1; then
        echo "       ERROR: Codex binary failed its version check" >&2
        return 1
    fi
    export CODEX_RESOLVED_VERSION="${FETCHED_VERSION}"
    echo "       Installed $("${install_dir}/bin/codex" --version)"
}

# codex-acp, the ACP adapter for Codex. Its npm package is one self-contained
# script, run by the pinned Node.js through the bin/codex-acp wrapper.
install_codex_acp() {
    local install_dir=$1
    local cache_dir=$2
    local bp_dir=$3
    local arch members

    arch=$(host_architecture) || return 1
    fetch_verified codex-acp "${arch}" "${cache_dir}" "${bp_dir}" CODEX_ACP || return 1

    if ! members=$(archive_members "${FETCHED_ARCHIVE}") \
        || ! grep -qx 'package/dist/index.js' <<< "${members}" \
        || ! grep -qx 'package/LICENSE' <<< "${members}"; then
        echo "       ERROR: codex-acp archive has unexpected or unsafe contents" >&2
        return 1
    fi

    rm -rf "${install_dir}/codex-acp"
    mkdir -p "${install_dir}/codex-acp" "${install_dir}/bin"
    tar xzf "${FETCHED_ARCHIVE}" -C "${install_dir}/codex-acp" --strip-components=2 \
        package/dist/index.js
    tar xzf "${FETCHED_ARCHIVE}" -C "${install_dir}/codex-acp" --strip-components=1 \
        package/LICENSE
    cp "${bp_dir}/lib/codex-acp-wrapper.sh" "${install_dir}/bin/codex-acp"
    chmod 0755 "${install_dir}/bin/codex-acp"

    if ! "${install_dir}/bin/codex-acp" --version >/dev/null 2>&1; then
        echo "       ERROR: codex-acp failed its version check" >&2
        return 1
    fi
    export CODEX_ACP_RESOLVED_VERSION="${FETCHED_VERSION}"
    echo "       Installed $("${install_dir}/bin/codex-acp" --version)"
}

get_codex_acp_version() {
    local install_dir=$1
    if [ -x "${install_dir}/bin/codex-acp" ]; then
        "${install_dir}/bin/codex-acp" --version 2>/dev/null || echo "unknown"
    else
        echo "not installed"
    fi
}

verify_installation() {
    local install_dir=$1
    local executable
    for executable in node/bin/node bin/codex bin/codex-acp; do
        [ -x "${install_dir}/${executable}" ] || {
            echo "       ERROR: ${executable} verification failed" >&2
            return 1
        }
        "${install_dir}/${executable}" --version >/dev/null 2>&1 || {
            echo "       ERROR: ${executable} cannot execute" >&2
            return 1
        }
    done
    echo "       Installation verified"
}
