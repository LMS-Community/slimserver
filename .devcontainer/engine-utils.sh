#!/usr/bin/env bash
# Shared helpers to detect a container engine command usable from shell scripts.

# Finds a container engine (podman or docker), preferring podman.
# Returns the command name or exits with error.
find_container_engine() {
	# Native Linux/macOS shell lookup
	if command -v podman >/dev/null 2>&1; then
		echo "podman"
		return 0
	fi
	if command -v docker >/dev/null 2>&1; then
		echo "docker"
		return 0
	fi

	# Windows executables may only be visible as *.exe from Git Bash/WSL
	if command -v podman.exe >/dev/null 2>&1; then
		echo "podman.exe"
		return 0
	fi
	if command -v docker.exe >/dev/null 2>&1; then
		echo "docker.exe"
		return 0
	fi

	# Fallback via where.exe when command -v does not see Windows PATH entries
	if command -v where.exe >/dev/null 2>&1; then
		local resolved
		resolved="$(where.exe podman 2>/dev/null | tr -d '\r' | head -n 1 || true)"
		if [[ -n "$resolved" ]]; then
			echo "$resolved"
			return 0
		fi
		resolved="$(where.exe docker 2>/dev/null | tr -d '\r' | head -n 1 || true)"
		if [[ -n "$resolved" ]]; then
			echo "$resolved"
			return 0
		fi
	fi

	return 1
}

# Finds a container engine that supports the 'compose' subcommand.
# On Windows / Git Bash the plain 'podman' may be a shim without compose support,
# while 'podman.exe' works correctly — this function tests each candidate in order.
find_compose_engine() {
	local candidates=()

	# Build the candidate list: prefer plain names, then .exe variants
	for name in podman docker; do
		command -v "$name"     >/dev/null 2>&1 && candidates+=("$name")
		command -v "$name.exe" >/dev/null 2>&1 && candidates+=("$name.exe")
	done

	# where.exe fallback for Git Bash / MSYS environments
	if command -v where.exe >/dev/null 2>&1; then
		for name in podman docker; do
			local resolved
			resolved="$(where.exe "$name" 2>/dev/null | tr -d '\r' | head -n 1 || true)"
			[[ -n "$resolved" ]] && candidates+=("$resolved")
		done
	fi

	for candidate in "${candidates[@]}"; do
		if "$candidate" compose version >/dev/null 2>&1; then
			echo "$candidate"
			return 0
		fi
	done

	return 1
}
