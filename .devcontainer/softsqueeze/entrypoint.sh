#!/usr/bin/env bash
# Entrypoint for standalone SoftSqueeze + VNC container.
# Starts Xvfb, fluxbox, x11vnc, noVNC, PulseAudio and SoftSqueeze.

set -euo pipefail

export DISPLAY=:99

LMS_HOST="${LMS_HOST:-lyrion-devcontainer}"
LMS_HTTP_PORT="${LMS_HTTP_PORT:-9000}"
LMS_SLIMPROTO_PORT="${LMS_SLIMPROTO_PORT:-3483}"
SOFTSQUEEZE_HOME="${SOFTSQUEEZE_HOME:-/opt/softsqueeze}"
SOFTSQUEEZE_PREFS_DIR="${SOFTSQUEEZE_PREFS_DIR:-/root/.softsqueeze-prefs}"
SOFTSQUEEZE_JAVA_OPTS="${SOFTSQUEEZE_JAVA_OPTS:--Xms32m -Xmx128m}"

start_if_missing() {
	local pattern="$1"
	shift
	if ! pgrep -f "$pattern" >/dev/null 2>&1; then
		"$@" &
	fi
}

# PulseAudio
pulseaudio --check >/dev/null 2>&1 || pulseaudio --start --exit-idle-time=-1 >/dev/null 2>&1 || true

if command -v pactl >/dev/null 2>&1; then
	sleep 1
	if ! pactl list short sinks 2>/dev/null | grep -q softsqueeze_sink; then
		pactl load-module module-null-sink sink_name=softsqueeze_sink \
			sink_properties=device.description=SoftSqueezeSink >/dev/null 2>&1 || true
	fi
	pactl set-default-sink softsqueeze_sink >/dev/null 2>&1 || true
fi

cat > /root/.asoundrc <<'EOF'
pcm.!default {
	type pulse
}
ctl.!default {
	type pulse
}
EOF

# VNC stack
echo "[INFO] Starting Xvfb"
start_if_missing "Xvfb :99" Xvfb :99 -screen 0 1280x1024x24
sleep 2

echo "[INFO] Starting fluxbox"
start_if_missing "fluxbox" fluxbox

echo "[INFO] Starting x11vnc"
start_if_missing "x11vnc -display :99" x11vnc -display :99 -forever -shared -nopw -ncache 10 -ncache_cr

if [[ -x /usr/share/novnc/utils/novnc_proxy ]]; then
	echo "[INFO] Starting noVNC"
	start_if_missing "novnc_proxy --vnc localhost:5900 --listen 6080" \
		/usr/share/novnc/utils/novnc_proxy --vnc localhost:5900 --listen 6080
fi

for ((i = 1; i <= 30; i++)); do
	if ss -ltn | grep -q ':6080'; then
		echo "[INFO] noVNC ready on port 6080"
		break
	fi
	sleep 1
done

# SoftSqueeze
mkdir -p "$SOFTSQUEEZE_PREFS_DIR"

echo "[INFO] LMS target: ${LMS_HOST}:${LMS_HTTP_PORT}"

cd "$SOFTSQUEEZE_HOME"

echo "[INFO] Starting SoftSqueeze"
read -r -a JAVA_OPTS <<< "$SOFTSQUEEZE_JAVA_OPTS"

java \
	"${JAVA_OPTS[@]}" \
	-Djava.util.prefs.userRoot="$SOFTSQUEEZE_PREFS_DIR" \
	-Dslimserver="$LMS_HOST" \
	-Dhttpport="$LMS_HTTP_PORT" \
	-Dslimport="$LMS_SLIMPROTO_PORT" \
	-Dcom.Ostermiller.util.Browser.open="xdg-open {0}" \
	-jar SoftSqueeze.jar \
	2>&1 | tee /tmp/softsqueeze.log &

SQUEEZE_PID=$!

echo "[INFO] SoftSqueeze PID: $SQUEEZE_PID"
echo "[INFO] noVNC: http://localhost:6080/vnc.html"

wait "$SQUEEZE_PID" || true

echo "[WARN] SoftSqueeze process exited. Keeping container alive for noVNC access."
exec tail -f /dev/null
