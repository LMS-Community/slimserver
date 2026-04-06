#!/usr/bin/env bash
# Manage SoftSqueeze + VNC standalone container.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
ENGINE=""

log_info() {
	echo "[INFO] $*"
}

log_error() {
	echo "[ERROR] $*" >&2
}

compose_run() {
	"$ENGINE" compose "$@"
}

if command -v podman >/dev/null 2>&1; then
	ENGINE="podman"
elif command -v docker >/dev/null 2>&1; then
	ENGINE="docker"
else
	log_error "Missing container engine (podman or docker)."
	exit 1
fi

log_info "Using container engine: $ENGINE"

if ! compose_run version >/dev/null 2>&1; then
	log_error "'$ENGINE compose' is not available."
	log_error "Install a version of $ENGINE with Compose support."
	exit 1
fi

# Default to Dev Container hostname on shared lyrion_bridge network.
export LMS_HOST="${LMS_HOST:-lyrion-devcontainer}"

case "${1:-start}" in
	start)
		log_info "Building and starting SoftSqueeze container..."
		if compose_run -f "$COMPOSE_FILE" up -d --build; then
			log_info "SoftSqueeze started successfully."
			log_info "Access points:"
			log_info "  noVNC:  http://localhost:6080/vnc.html"
			log_info "  VNC:    localhost:5900"
			log_info "Stop with: $SCRIPT_NAME stop"
		else
			log_error "Failed to start SoftSqueeze."
			exit 1
		fi
		;;
	stop)
		log_info "Stopping SoftSqueeze container..."
		if compose_run -f "$COMPOSE_FILE" down; then
			log_info "SoftSqueeze stopped."
		else
			log_error "Failed to stop SoftSqueeze."
			exit 1
		fi
		;;
	status)
		log_info "SoftSqueeze container status:"
		compose_run -f "$COMPOSE_FILE" ps
		;;
	logs)
		log_info "Tailing SoftSqueeze logs (Ctrl+C to exit)..."
		compose_run -f "$COMPOSE_FILE" logs -f
		;;
	*)
		log_error "Invalid command: ${1:-start}"
		log_info "Usage: $SCRIPT_NAME {start|stop|status|logs}"
		exit 1
		;;
esac
