#!/usr/bin/env bash
# Downloads Slim/Utils/OS/Custom.pm from slimserver-platforms.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BRANCH="$(git -c safe.directory="$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
BASE_URL="https://raw.githubusercontent.com/LMS-Community/slimserver-platforms"
TARGET_FILE="$REPO_ROOT/Slim/Utils/OS/Custom.pm"

echo "[INFO] Post-create setup"
git config --global --add safe.directory "$REPO_ROOT" 2>/dev/null || true

mkdir -p "$(dirname "$TARGET_FILE")"

echo "[INFO] Downloading Custom.pm for branch: $BRANCH"
if curl -fsSL "${BASE_URL}/${BRANCH}/Docker/Slim-Utils-OS-Custom.pm" -o "$TARGET_FILE" 2>/dev/null; then
	echo "[INFO] Downloaded from branch '$BRANCH'"
elif curl -fsSL "${BASE_URL}/HEAD/Docker/Slim-Utils-OS-Custom.pm" -o "$TARGET_FILE" 2>/dev/null; then
	echo "[INFO] Downloaded from fallback 'HEAD'"
else
	echo "[ERROR] Failed to download Custom.pm" >&2
	exit 1
fi

