#!/usr/bin/env bash
# Manage SoftSqueeze + VNC standalone container.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
COMPOSE_FILE_FOR_ENGINE="$COMPOSE_FILE"
ENGINE=""

source "$SCRIPT_DIR/../engine-utils.sh"

log_info() {
	echo "[INFO] $*"
}

log_error() {
	echo "[ERROR] $*" >&2
}

compose_run() {
	"$ENGINE" compose "$@"
}

ENGINE="$(find_compose_engine || true)"

if [[ -z "$ENGINE" ]]; then
	log_error "No container engine with 'compose' support found (podman or docker)."
	log_error "On Windows / Git Bash try running the script directly (without 'bash' prefix)."
	exit 1
fi

log_info "Using container engine: $ENGINE"

if [[ "$ENGINE" == *.exe ]]; then
	if command -v cygpath >/dev/null 2>&1; then
		COMPOSE_FILE_FOR_ENGINE="$(cygpath -w "$COMPOSE_FILE")"
	elif command -v wslpath >/dev/null 2>&1; then
		COMPOSE_FILE_FOR_ENGINE="$(wslpath -w "$COMPOSE_FILE")"
	fi
fi

# Default to Dev Container hostname on shared lyrion_bridge network.
export LMS_HOST="${LMS_HOST:-lyrion-devcontainer}"

case "${1:-start}" in
	start)
		log_info "Building and starting SoftSqueeze container..."
		if compose_run -f "$COMPOSE_FILE_FOR_ENGINE" up -d --build; then
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
		if compose_run -f "$COMPOSE_FILE_FOR_ENGINE" down; then
			log_info "SoftSqueeze stopped."
		else
			log_error "Failed to stop SoftSqueeze."
			exit 1
		fi
		;;
	status)
		log_info "SoftSqueeze container status:"
		compose_run -f "$COMPOSE_FILE_FOR_ENGINE" ps
		;;
	logs)
		log_info "Tailing SoftSqueeze logs (Ctrl+C to exit)..."
		compose_run -f "$COMPOSE_FILE_FOR_ENGINE" logs -f
		;;
	*)
		log_error "Invalid command: ${1:-start}"
		log_info "Usage: $SCRIPT_NAME {start|stop|status|logs}"
		exit 1
		;;
esac
