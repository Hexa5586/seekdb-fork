#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

export LD_LIBRARY_PATH="$PWD/deps/3rd/u01/obclient/lib:$PWD/deps/3rd/usr/local/oceanbase/deps/devel/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

port="${SEEKDB_PORT:-2881}"

exec deps/3rd/u01/obclient/bin/obclient -h127.0.0.1 -P"$port" -uroot -A "$@"
