#!/usr/bin/env bash
# version.sh — Read the root VERSION file and export APP_VERSION.
# Usage: source scripts/version.sh
#        echo $APP_VERSION
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="${SCRIPT_DIR}/../VERSION"

if [[ ! -f "$VERSION_FILE" ]]; then
    echo "[version.sh] ERROR: VERSION file not found at ${VERSION_FILE}" >&2
    exit 1
fi

APP_VERSION="$(cat "$VERSION_FILE" | tr -d '[:space:]')"

if [[ -z "$APP_VERSION" ]]; then
    echo "[version.sh] ERROR: VERSION file is empty" >&2
    exit 1
fi

export APP_VERSION
echo "[version.sh] APP_VERSION=${APP_VERSION}"
