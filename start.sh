#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

export LD_LIBRARY_PATH="$PWD/deps/3rd/usr/local/oceanbase/deps/devel/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

base_dir="${SEEKDB_BASE_DIR:-$PWD/build/dev-instance}"
port="${SEEKDB_PORT:-2881}"
client="$PWD/deps/3rd/u01/obclient/bin/obclient"

python3 tools/deploy/sdb.py start \
  --binary build/bin/src/observer/seekdb \
  --base-dir "$base_dir" --port "$port" "$@"
python3 tools/deploy/sdb.py wait-ready \
  --client "$client" --base-dir "$base_dir" --port "$port"
