# Threat model

`pi-docker` assumes that the agent may misbehave, through prompt injection
from a file, a web page or a dependency, or through a plain mistake. It limits
the damage to the project you started it in.

## What the container protects

| Asset | How |
|---|---|
| Files outside the project | Only the current directory and `~/.pi-docker` are mounted. Running in `/` or your home directory is refused. |
| Host credentials | `~/.ssh`, `~/.aws`, `~/.gitconfig`, keychains, cloud CLIs and the Docker socket are never mounted. Host variables only pass with `--env`. |
| Host pi config | The host `~/.pi` is never mounted, so the agent cannot plant extensions, `AGENTS.md` instructions or settings that an unsandboxed pi later loads. |
| The image | Read-only root filesystem. pi is installed as root and owned by root. Nothing the agent installs survives the run. |
| Privilege escalation | Unprivileged user, all capabilities dropped, `no-new-privileges`, no setuid binaries, no `sudo`. |
| Host resources | Memory, process and optional CPU limits. tmpfs mounts are size-limited. |
| Git hooks | `.git/hooks` and `.git/config` are read-only, so the agent cannot add a hook, `core.hooksPath`, `core.fsmonitor` or a filter driver that git on the host would run. |
| Network exposure | No ports are published, except the OAuth callback ports during `--login`, and then only on `127.0.0.1`. |

## What the container does NOT protect

**The project directory.** The agent can read, change and delete every file
in it. Use git and review the diff before you trust the result.

**Code in the project that the host runs later.** The agent can edit anything
your tools execute: `Makefile`, `package.json` scripts, `.envrc` (direnv),
`.vscode/tasks.json`, `pyproject.toml` build hooks, test files, CI workflows,
pre-commit configs. When you run `make`, `npm install` or open the folder in an
IDE that trusts it, that code runs **on your host without a sandbox**. Review
changes to such files before you run them on the host. Better still, run them
in the container (`pi-docker --shell`).

**Network access.** The container has full outbound network access. The agent
can upload project files, or your pi credentials, anywhere. An egress
allowlist is planned but not built yet.

**Your pi credentials.** The agent can read `~/.pi/agent/auth.json` inside the
container; pi needs it. Use a login or an API key you can revoke, and revoke
it if you suspect misuse.

**Variables passed with `--env`.** Anything you pass in, the agent can read.

**Sharing commands.** `/share` uploads the whole session and `/bug` uploads a
report. Sessions can contain file contents and secrets that appeared in the
conversation. Review them before you share. See the privacy section of the
README for the requests pi makes on its own.

**Paths shared with `--mount-ro`.** They are read-only, but the agent can read
and upload them.

**The container runtime.** A kernel or runtime bug can break any container.
Docker Desktop, OrbStack, Colima and Podman machine on macOS and Windows add a
virtual machine as a second boundary. On Linux, keep the kernel and the
runtime patched. Rootless Podman adds a user namespace.

**Malicious packages.** pi packages and extensions you install run inside the
container with the same rights as the agent.

## Escape hatches

| Option | Risk |
|---|---|
| `--unsafe-git` | The agent can install git hooks that run on your host. |
| `--env NAME` | The agent can read the value. |
| `--mount-ro PATH` | The agent can read and upload the path. |
| `PI_DOCKER_HOME=~/.pi` | The agent can change your host pi config. Never do this. |
| `PI_DOCKER_USER=0:0` | pi has root rights in the container. Only for rootless engines. |
