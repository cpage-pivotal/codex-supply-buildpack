#!/bin/sh
# Installed as bin/codex-acp. codex-acp is a Node.js program: run it on the
# pinned Node.js, against the codex binary beside this script. Paths are
# relative to this script, so the droplet works wherever $DEPS_DIR is mounted.

bin_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(dirname -- "${bin_dir}")
: "${CODEX_PATH:=${bin_dir}/codex}"
export CODEX_PATH
exec "${root}/node/bin/node" "${root}/codex-acp/index.js" "$@"
