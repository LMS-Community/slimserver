#!/usr/bin/env bash
# Creates shared network for DevContainer + SoftSqueeze.

set -euo pipefail

readonly NETWORK_NAME="lyrion_bridge"
ENGINE=""

if command -v podman >/dev/null 2>&1; then
	ENGINE="podman"
elif command -v docker >/dev/null 2>&1; then
	ENGINE="docker"
else
	echo "[ERROR] Missing container engine (podman or docker)." >&2
	exit 1
fi

echo "[INFO] Using container engine: $ENGINE"

if $ENGINE network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
	echo "[INFO] Network '$NETWORK_NAME' already exists, skipping creation."
	exit 0
fi

echo "[INFO] Creating network '$NETWORK_NAME'..."
if $ENGINE network create "$NETWORK_NAME" --driver=bridge; then
	echo "[INFO] Network '$NETWORK_NAME' created successfully."
else
	echo "[ERROR] Failed to create network '$NETWORK_NAME'." >&2
	exit 1
fi
