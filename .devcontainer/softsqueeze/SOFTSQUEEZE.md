# SoftSqueeze — Standalone Container

[SoftSqueeze](https://lyrion.org/players-and-controllers/softsqueeze/) + VNC runs as a separate optional container and connects to LMS running in the Dev Container.
LMS works normally even when SoftSqueeze is not running.

> [!NOTE]
> This container is intended primarily for **display simulation** of the SoftSqueeze player.
>
> **Audio is not supported** in this container. SoftSqueeze acts only as a visual client for LMS.
> Container audio uses PulseAudio with a null sink to avoid Java mixer errors and allow player registration.

## Prerequisites

- LMS is running (default HTTP port `9000`).
- Podman or Docker is installed on the host.
- Shared network `lyrion_bridge` exists (created by [`.devcontainer/initialize.sh`](../initialize.sh)).

## Quick Start

1. Make sure LMS is running.
2. Start SoftSqueeze from your host terminal (not inside the Dev Container) [^1]:
   ```bash
   bash .devcontainer/softsqueeze/softsqueeze.sh start
   ```

[^1]: You can also run Compose directly:

    ```bash
    podman compose -f .devcontainer/softsqueeze/docker-compose.yml up -d
    podman compose -f .devcontainer/softsqueeze/docker-compose.yml down
    # or
    docker compose -f .devcontainer/softsqueeze/docker-compose.yml up -d
    docker compose -f .devcontainer/softsqueeze/docker-compose.yml down
    ```

> [!TIP]
> If it fails to start, try running the command without `bash` to use your default shell environment:
>
> ```bash
> .devcontainer/softsqueeze/softsqueeze.sh start
> ```

3. Open noVNC in your browser [http://localhost:6080/vnc.html](http://localhost:6080/vnc.html) and connect to the VNC server.

4. SoftSqueeze should appear in VNC and register in LMS as a player.

## Management

```bash
# Start (build + run)
bash .devcontainer/softsqueeze/softsqueeze.sh start

# Stop + remove
bash .devcontainer/softsqueeze/softsqueeze.sh stop

# Show status
bash .devcontainer/softsqueeze/softsqueeze.sh status

# Tail logs
bash .devcontainer/softsqueeze/softsqueeze.sh logs
```

The launcher auto-detects Podman or Docker.

## Connection Defaults

| Environment Variable | Default               | Description                                     |
| -------------------- | --------------------- | ----------------------------------------------- |
| `LMS_HOST`           | `lyrion-devcontainer` | LMS hostname in shared `lyrion_bridge` network. |
| `LMS_HTTP_PORT`      | `9000`                | LMS HTTP port                                   |
| `LMS_SLIMPROTO_PORT` | `3483`                | SlimProto port                                  |

Override via environment variables:

```bash
LMS_HOST=192.168.1.100 bash .devcontainer/softsqueeze/softsqueeze.sh start
```

Or edit the environment section in [`.devcontainer/softsqueeze/docker-compose.yml`](docker-compose.yml).

> [!TIP]
> If SoftSqueeze cannot connect after changing host settings, set host back to:
>
> ```bash
> LMS_HOST=lyrion-devcontainer bash .devcontainer/softsqueeze/softsqueeze.sh start
> ```

## How It Works

- The SoftSqueeze container runs Xvfb + fluxbox + x11vnc + noVNC + PulseAudio + SoftSqueeze.
- Exposes port `6080` (noVNC web) and `5900` (VNC).

## Troubleshooting

### SoftSqueeze Cannot Connect to LMS

1. Confirm LMS port `9000` is accessible from host:

```bash
curl -sS http://localhost:9000/ | head -c 100
```

2. Verify shared network exists:

```bash
podman network inspect lyrion_bridge
# or
docker network inspect lyrion_bridge
```

3. Check SoftSqueeze logs:

```bash
bash .devcontainer/softsqueeze/softsqueeze.sh logs
```
