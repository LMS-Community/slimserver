#!/usr/bin/env bash
# Stops running LMS process.

set -euo pipefail

readonly FORCE="${FORCE:-0}"

if ! pgrep -f 'perl .*slimserver\.pl' >/dev/null 2>&1; then
	echo "[INFO] LMS is not running."
	exit 0
fi

if [[ "$FORCE" == "1" ]]; then
	echo "[INFO] Stopping LMS (SIGKILL)"
	pkill -9 -f 'perl .*slimserver\.pl' || true
else
	echo "[INFO] Stopping LMS (SIGTERM)"
	pkill -15 -f 'perl .*slimserver\.pl' || true
	sleep 2
	if pgrep -f 'perl .*slimserver\.pl' >/dev/null 2>&1; then
		echo "[WARN] LMS still running, forcing SIGKILL"
		pkill -9 -f 'perl .*slimserver\.pl' || true
	fi
fi

if pgrep -f 'perl .*slimserver\.pl' >/dev/null 2>&1; then
	echo "[ERROR] Failed to stop LMS" >&2
	exit 1
fi

echo "[INFO] LMS stopped"
