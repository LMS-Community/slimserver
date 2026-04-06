#!/usr/bin/env bash
# Cleans runtime-generated folders.

set -euo pipefail

readonly FORCE="${FORCE:-0}"

# Folders to remove (runtime-generated, in .gitignore)
readonly FOLDERS_TO_CLEAN=(
	"Cache"
	"Logs"
	"prefs"
)
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

if [[ "$FORCE" != "1" ]]; then
	echo "[INFO] This will delete: ${FOLDERS_TO_CLEAN[*]}"
	echo "[INFO] Re-run with FORCE=1 to continue"
	exit 0
fi

DELETED=0
for folder in "${FOLDERS_TO_CLEAN[@]}"; do
	if [[ -d "$folder" ]]; then
		echo "[INFO] Deleting $folder/"
		rm -rf "$folder"
		DELETED=$((DELETED + 1))
	fi
done

echo "[INFO] Cleanup complete ($DELETED folder(s) removed)"

