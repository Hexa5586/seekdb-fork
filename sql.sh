#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

export LD_LIBRARY_PATH="$PWD/deps/3rd/u01/obclient/lib:$PWD/deps/3rd/usr/local/oceanbase/deps/devel/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# The bundled readline only looks in /usr/share/terminfo, which is empty on
# Debian/Ubuntu; without the real entry, Backspace appends spaces instead of
# erasing and cursor keys stop working.
if [ -z "${TERMINFO:-}" ] && [ -z "${TERMINFO_DIRS:-}" ]; then
  export TERMINFO_DIRS=/lib/terminfo:/usr/share/terminfo:/etc/terminfo
fi

port="${SEEKDB_PORT:-2881}"

exec deps/3rd/u01/obclient/bin/obclient -h127.0.0.1 -P"$port" -uroot -A "$@"
