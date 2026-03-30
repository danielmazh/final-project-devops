#!/usr/bin/env bash
# change-detect.sh — Classify git changes into build targets.
#
# Outputs (exported env vars):
#   BUILD_ENGINE=true|false
#   BUILD_CLI=true|false
#
# Usage: source scripts/change-detect.sh
#        echo "Engine: $BUILD_ENGINE  CLI: $BUILD_CLI"
#
# In Jenkins, call as:
#   . scripts/change-detect.sh
#   echo "BUILD_ENGINE=${BUILD_ENGINE}" > build.env  (then load with envFile)
set -euo pipefail

BUILD_ENGINE=false
BUILD_CLI=false

# Files changed in the last commit (or all files if first commit / squash)
if git rev-parse HEAD~1 >/dev/null 2>&1; then
    CHANGED=$(git diff HEAD~1 --name-only 2>/dev/null || true)
else
    # First commit — build everything
    CHANGED=$(git diff-tree --no-commit-id -r --name-only HEAD 2>/dev/null || true)
fi

if [[ -z "$CHANGED" ]]; then
    echo "[change-detect] No file changes detected — skipping builds."
    export BUILD_ENGINE BUILD_CLI
    exit 0
fi

# VERSION change always triggers both
if echo "$CHANGED" | grep -qE "^VERSION$"; then
    BUILD_ENGINE=true
    BUILD_CLI=true
    echo "[change-detect] VERSION changed → BUILD_ENGINE=true BUILD_CLI=true"
    export BUILD_ENGINE BUILD_CLI
    exit 0
fi

# Engine paths
if echo "$CHANGED" | grep -qE "^(engine/|docker/engine/|engine/configuration/)"; then
    BUILD_ENGINE=true
fi

# CLI paths
if echo "$CHANGED" | grep -qE "^(cli/|docker/cli/)"; then
    BUILD_CLI=true
fi

echo "[change-detect] BUILD_ENGINE=${BUILD_ENGINE}  BUILD_CLI=${BUILD_CLI}"
echo "[change-detect] Changed files:"
echo "$CHANGED" | sed 's/^/  /'

export BUILD_ENGINE BUILD_CLI
