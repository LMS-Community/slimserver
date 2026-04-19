#!/usr/bin/env bash
# Starts LMS. Config is always /config.

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly HTTP_PORT="${LMS_HTTP_PORT:-9000}"
readonly LMS_WAIT_TIMEOUT="${LMS_WAIT_TIMEOUT:-90}"
readonly LOGFILE="/tmp/devcontainer-lms.log"
readonly LMS_EXTRA_ARGS="${LMS_EXTRA_ARGS:-${EXTRA_ARGS:-}}"

is_lms_running() {
	pgrep -f 'perl .*slimserver\.pl' >/dev/null 2>&1
}

if is_lms_running; then
	echo "[INFO] LMS is already running."
	exit 0
fi

mkdir -p /config/prefs /config/logs /config/cache

declare -a extra_args=()
if [[ -n "$LMS_EXTRA_ARGS" ]]; then
	read -r -a extra_args <<< "$LMS_EXTRA_ARGS"
fi

echo "[INFO] Starting LMS on port $HTTP_PORT"
nohup perl "$REPO_ROOT/slimserver.pl" \
	--prefsdir /config/prefs \
	--logdir   /config/logs \
	--cachedir /config/cache \
	--httpport "$HTTP_PORT" \
	"${extra_args[@]}" \
	>"$LOGFILE" 2>&1 &

for _ in $(seq 1 "$LMS_WAIT_TIMEOUT"); do
	if curl -fsS "http://127.0.0.1:${HTTP_PORT}/" >/dev/null 2>&1; then
		echo "[INFO] LMS reachable at http://127.0.0.1:$HTTP_PORT"
		echo "[INFO] Log: $LOGFILE"
		exit 0
	fi
	sleep 1
done

echo "[WARN] LMS did not become reachable in ${LMS_WAIT_TIMEOUT}s" >&2
echo "[WARN] Check log: $LOGFILE" >&2
exit 1
