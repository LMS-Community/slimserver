#!/usr/bin/env bash
# Creates the shared network for the Dev Container and SoftSqueeze.

set -euo pipefail

readonly NETWORK_NAME="lyrion_bridge"
ENGINE=""

source "$(dirname "$0")/engine-utils.sh"

ENGINE="$(find_container_engine || true)"

if [[ -z "$ENGINE" ]]; then
	echo "[ERROR] Missing container engine (podman or docker)." >&2
	echo "[ERROR] Make sure it is installed and available in the shell PATH used by initializeCommand." >&2
	exit 1
fi

echo "[INFO] Using container engine: $ENGINE"

if "$ENGINE" network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
	echo "[INFO] Network '$NETWORK_NAME' already exists, skipping creation."
	exit 0
fi

echo "[INFO] Creating network '$NETWORK_NAME'..."
if "$ENGINE" network create "$NETWORK_NAME" --driver=bridge; then
	echo "[INFO] Network '$NETWORK_NAME' created successfully."
else
	echo "[ERROR] Failed to create network '$NETWORK_NAME'." >&2
	exit 1
fi
