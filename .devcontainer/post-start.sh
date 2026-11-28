#!/usr/bin/env bash
# Starts LMS when AUTO_START_LMS=true.

set -euo pipefail

readonly AUTO_START_LMS="${AUTO_START_LMS:-false}"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "$AUTO_START_LMS" != "true" ]]; then
	echo "[INFO] AUTO_START_LMS=false, skipping LMS startup."
	exit 0
fi

exec bash "$SCRIPT_DIR/start-lyrion.sh"
