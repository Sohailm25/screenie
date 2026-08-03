#!/usr/bin/env bash

set -euo pipefail

DEVELOPER_PATH="$(/usr/bin/xcode-select -p)"
TESTING_FRAMEWORKS="${DEVELOPER_PATH}/Library/Developer/Frameworks"
DEVELOPER_USR_LIB="${DEVELOPER_PATH}/Library/Developer/usr/lib"

if [[ -d "${TESTING_FRAMEWORKS}/Testing.framework" ]]; then
    exec /usr/bin/env swift test \
        -Xswiftc -F \
        -Xswiftc "${TESTING_FRAMEWORKS}" \
        -Xlinker -F \
        -Xlinker "${TESTING_FRAMEWORKS}" \
        -Xlinker -rpath \
        -Xlinker "${TESTING_FRAMEWORKS}" \
        -Xlinker -rpath \
        -Xlinker "${DEVELOPER_USR_LIB}" \
        "$@"
fi

exec /usr/bin/env swift test "$@"
