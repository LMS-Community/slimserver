#!/usr/bin/env bash
# Cleans runtime-generated folders in /config.

set -euo pipefail

readonly FORCE="${FORCE:-0}"

# Runtime-generated subdirectories (prefs, logs, cache)
readonly FOLDERS_TO_CLEAN=(
	"/config/prefs"
	"/config/logs"
	"/config/cache"
)

if [[ "$FORCE" != "1" ]]; then
	echo "[INFO] The following folders would be deleted:"
	for folder in "${FOLDERS_TO_CLEAN[@]}"; do
		if [[ -d "$folder" ]]; then
			echo "[INFO]   $folder/ (exists)"
		else
			echo "[INFO]   $folder/ (not found, skipped)"
		fi
	done
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
