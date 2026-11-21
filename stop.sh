#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

base_dir="${SEEKDB_BASE_DIR:-$PWD/build/dev-instance}"

python3 tools/deploy/sdb.py stop --base-dir "$base_dir" "$@"
