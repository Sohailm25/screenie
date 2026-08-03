#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${PROJECT_DIR}/dist"
APP_DIR="${DIST_DIR}/SnapText.app"
BUILD_ARCH="$(/usr/bin/uname -m)"
ZIP_PATH="${DIST_DIR}/SnapText-${BUILD_ARCH}.zip"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
INFO_PLIST="${PROJECT_DIR}/Resources/Info.plist"

if [[ ! -f "${PROJECT_DIR}/Package.swift" || ! -f "${INFO_PLIST}" ]]; then
    echo "Run this script from a complete SnapText checkout." >&2
    exit 1
fi

/usr/bin/plutil -lint "${INFO_PLIST}"

(
    cd "${PROJECT_DIR}"
    /usr/bin/env swift build -c release
)

BIN_DIR="$(cd "${PROJECT_DIR}" && /usr/bin/env swift build -c release --show-bin-path)"
EXECUTABLE="${BIN_DIR}/SnapText"

if [[ ! -x "${EXECUTABLE}" ]]; then
    echo "Release executable was not found at ${EXECUTABLE}." >&2
    exit 1
fi

/bin/mkdir -p "${DIST_DIR}"
/bin/rm -rf "${APP_DIR}"
/bin/rm -f "${DIST_DIR}/SnapText.zip" "${DIST_DIR}"/SnapText-*.zip
/bin/mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
/usr/bin/install -m 0755 "${EXECUTABLE}" "${MACOS_DIR}/SnapText"
/usr/bin/install -m 0644 "${INFO_PLIST}" "${CONTENTS_DIR}/Info.plist"

if [[ -x /usr/bin/codesign ]]; then
    /usr/bin/codesign --force --sign - --timestamp=none "${APP_DIR}"
fi

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${ZIP_PATH}"

echo "Built ${APP_DIR}"
echo "Created ${ZIP_PATH}"
echo "Architecture: ${BUILD_ARCH}"
