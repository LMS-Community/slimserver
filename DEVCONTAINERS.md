# Dev Container Environment

You can run the project either entirely in the cloud using GitHub Codespaces or locally using VS Code with Dev Containers. Both methods provide a fully configured environment without requiring manual setup on your machine.

## Development Modes

### 1. GitHub Codespaces
- In Github on the Code tab click the **Code Button** → **Codespaces** → **Create Codespace**.
- Wait for the browser-based VS Code to start.
- Run `slimserver` in the terminal.
- Open the **Ports** tab and click the forwarded port to access the SlimServer web UI.
- Note: Codespaces includes free-tier limitations.

### 2. Local VS Code with Dev Containers
- Install the Dev Containers extension: `ext install ms-vscode-remote.remote-containers` and make sure Dev Containers work.
- Run **Dev Containers: Clone Repository** command and follow the steps.
- The container builds automatically—no local dependencies required.
- After build completion, the environment is ready to use.
