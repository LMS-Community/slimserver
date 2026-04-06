# Dev Container Environment

You can run the project either entirely in the cloud using **GitHub Codespaces** or locally using **VS Code with Dev Containers**. Both methods provide a fully configured environment without requiring manual setup on your machine.

## Quick Start

Both methods are ready for Perl development, including support for the [Perl Language Server](https://github.com/richterger/Perl-LanguageServer).

### GitHub Codespaces

> [!IMPORTANT]
> Codespaces has free tier [limitations](https://docs.github.com/en/billing/concepts/product-billing/github-codespaces).

1. In GitHub on the **Code** tab, click **Code** button → **Codespaces** → **Create codespace on ...**.
2. Wait for the browser-based VS Code to start.
3. Continue with [Running Lyrion](#running-lyrion).

### Local VS Code + Dev Containers [^1]

[^1]: Podman and Docker are both supported.

    For Podman, set [`dev.containers.dockerPath`](vscode://settings/dev.containers.dockerPath) to `podman`, and set [`dev.containers.dockerComposePath`](vscode://settings/dev.containers.dockerComposePath) to `podman compose`.

> [!TIP]
> It is recommended to use at least 6GB of RAM for the Dev Container, especially if you plan to run SoftSqueeze alongside Lyrion. See the `memory` key in [WSL configuration](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#main-wsl-settings) for more details.

1. Install [Visual Studio Code](https://code.visualstudio.com/).
2. Install the [Dev Containers extension](vscode:extension/ms-vscode-remote.remote-containers) and make sure Dev Containers work on your machine. Follow the **Installation** instructions in the extension documentation.

> [!TIP]
> In VS Code, open the Command Palette and run [`ext install ms-vscode-remote.remote-containers`](vscode:extension/ms-vscode-remote.remote-containers) to install the extension.

3. Then you can either:
   - Open the cloned repository in VS Code and then open the Command Palette and run [`> Dev Containers: Reopen in Container`](command:remote-containers.reopenInContainer) command.
   - Alternatively, in VS Code, open the Command Palette and run [`> Dev Containers: Clone Repository in Container Volume`](command:remote-containers.openRepositoryFromGitWithEditSession) command and follow the steps.

4. Continue with [Running Lyrion](#running-lyrion).

#### Supported Modes

You can run the Dev Container in two ways (see [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json)):

- **Docker Compose mode**
- **Dockerfile mode**
  - Useful if you have issues with Compose or want a minimal setup.

Both modes mount your project to `/workspaces/slimserver` in the container and provide the same development environment.

## Running Lyrion

### Manual Start

1. Open a terminal in VS Code (should be in `/workspaces/slimserver`).
2. Run `perl slimserver.pl` [^2].

[^2]: You can set a different port than `9000` with `--httpport <port>` but this will require additional configuration changes.

3. Wait for the server to start, in the terminal you should see something like:
   ```
   Server done init: http://172.18.0.1:9000
   ```
4. Open the **Ports** tab and click the **Forwarded Address** `Web interface` to access Lyrion web UI [^3].
   [^3]: For local Dev Containers you can also open [http://localhost:9000](http://localhost:9000) directly.

### Auto-Start (`AUTO_START_LMS=true`)

The Dev Container can start Lyrion automatically. This is disabled by default.

1. Uncomment or set in [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json):
   ```json
   "containerEnv": {
       "AUTO_START_LMS": "true"
   }
   ```
2. Rebuild the container.
3. Lyrion will start automatically and listen on port `9000`.
4. To stop Lyrion without restarting the container:

   ```bash
   bash .devcontainer/stop-lyrion.sh
   # or force-kill
   FORCE=1 bash .devcontainer/stop-lyrion.sh
   ```

## SoftSqueeze [^4]

[^4]: Not supported in Codespaces. SoftSqueeze runs as a separate optional container.

Use the standalone guide in [.devcontainer/softsqueeze/SOFTSQUEEZE.md](.devcontainer/softsqueeze/SOFTSQUEEZE.md) for setup, runtime requirements, and troubleshooting.

## Debugging

### Debug Launch

1. Set a breakpoint.
2. Press **F5**.
3. Select **LMS: Debug slimserver.pl**.
4. LMS will launch in debug mode on port 9000.

Configuration is in [.vscode/launch.json](.vscode/launch.json).

> [!NOTE]
> **Debugger Stop Behavior**
>
> Due to the way Perl and LMS handle signals (see the adjustments in [.vscode/PerlLanguageServerBootstrap.pm](.vscode/PerlLanguageServerBootstrap.pm)), the debugger may not immediately respond to the first stop request. If you encounter this behavior, simply click the stop button again to ensure the debugger receives the signal and halts execution as expected.

## Cleanup

### Remove Runtime Folders

```bash
# For preview
bash .devcontainer/clean-folders.sh
# For actual cleanup
FORCE=1 bash .devcontainer/clean-folders.sh
```

This removes:

- `Cache/`
- `Logs/`
- `prefs/`

## Troubleshooting

### Port 9000 Not Accessible

1. Verify Lyrion is running inside the container:
   ```bash
   ss -ltn | grep 9000
   ```
2. Check logs:
   ```bash
   tail -f /tmp/devcontainer-lms.log
   ```
3. Rebuild the Dev Container.

## Notes

- Lyrion ports `9000`, `3483`, and `9090` are forwarded by default.
- Lyrion and SoftSqueeze use the `lyrion_bridge` network.

## Further Reading

- [Dev Containers Documentation](https://containers.dev/)
- [VS Code Remote Development](https://code.visualstudio.com/docs/remote/remote-overview)
- [Perl Language Server](https://github.com/richterger/Perl-LanguageServer)
