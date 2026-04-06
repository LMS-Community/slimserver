#!/usr/bin/env bash
# Starts LMS when AUTO_START_LMS=true.

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly AUTO_START_LMS="${AUTO_START_LMS:-false}"
readonly LMS_HTTP_PORT="${LMS_HTTP_PORT:-9000}"
readonly LMS_WAIT_TIMEOUT="${LMS_WAIT_TIMEOUT:-90}"
readonly LOGFILE="/tmp/devcontainer-lms.log"

is_lms_running() {
	pgrep -f 'perl .*slimserver\.pl' >/dev/null 2>&1
}

if [[ "$AUTO_START_LMS" != "true" ]]; then
	echo "[INFO] AUTO_START_LMS=false, skipping LMS startup."
	exit 0
fi

if is_lms_running; then
	echo "[INFO] LMS already running."
	exit 0
fi

echo "[INFO] Starting LMS on port $LMS_HTTP_PORT"
nohup perl "$REPO_ROOT/slimserver.pl" \
	--httpport "$LMS_HTTP_PORT" \
	>"$LOGFILE" 2>&1 &

CONTAINER_IP="$(hostname -I | awk '{print $1}' || true)"

for _ in $(seq 1 "$LMS_WAIT_TIMEOUT"); do
	if curl -fsS "http://127.0.0.1:${LMS_HTTP_PORT}/" >/dev/null 2>&1; then
		echo "[INFO] LMS reachable at 127.0.0.1:$LMS_HTTP_PORT"
		echo "[INFO] Log: $LOGFILE"
		exit 0
	fi

	if [[ -n "$CONTAINER_IP" ]] && curl -fsS "http://${CONTAINER_IP}:${LMS_HTTP_PORT}/" >/dev/null 2>&1; then
		echo "[INFO] LMS reachable at ${CONTAINER_IP}:$LMS_HTTP_PORT"
		echo "[INFO] Log: $LOGFILE"
		exit 0
	fi

	sleep 1
done

echo "[WARN] LMS did not become reachable in ${LMS_WAIT_TIMEOUT}s" >&2
echo "[WARN] Check log: $LOGFILE" >&2
exit 1
