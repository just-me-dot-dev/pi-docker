<div align="center">

# pi-docker

**Run the [pi](https://pi.dev) coding agent in a hardened container.**

[![build](https://github.com/just-me-dot-dev/pi-docker/actions/workflows/build.yml/badge.svg)](https://github.com/just-me-dot-dev/pi-docker/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)
![Engines](https://img.shields.io/badge/engines-Docker%20%7C%20Podman-2496ED)

</div>

pi runs shell commands on your behalf, without asking before each one. That is
what makes it useful, and also what makes it risky: a prompt injection in a
README, a web page or a dependency can steer it. `pi-docker` runs pi in a
locked-down container that can reach the project you started it in, and
nothing else on your machine.

```sh
cd ~/code/my-project
pi-docker            # exactly like pi, but contained
```

## Contents

- [Features](#features)
- [Quick start](#quick-start)
- [Installation](#installation)
- [Usage](#usage)
- [Configuration](#configuration)
- [Authentication](#authentication)
- [Customization](#customization)
- [Privacy](#privacy)
- [Security](#security)
- [Platform support](#platform-support)
- [Troubleshooting](#troubleshooting)
- [Development](#development)
- [License](#license)

## Features

- **Least privilege.** pi runs as an unprivileged user with all Linux
  capabilities dropped, `no-new-privileges`, and no setuid binaries.
- **Immutable image.** The root filesystem is read-only. pi cannot change its
  own code, and nothing it installs survives the run.
- **Minimal mounts.** Only the current directory and a dedicated pi state
  directory are mounted. Your home directory, SSH keys, cloud credentials and
  the Docker socket stay out of reach.
- **Persistent login.** Log in once; every later container reuses the login.
- **Host pi stays clean.** Your host `~/.pi` is never mounted, so the agent
  cannot plant extensions or instructions that an unsandboxed pi would load.
- **Git hook protection.** `.git/hooks` and `.git/config` are read-only, so
  the agent cannot make git on your host run code.
- **Resource limits.** Memory, process and optional CPU limits.
- **Privacy defaults.** pi's install report and version check are turned off.
- **Cross-platform.** macOS, Linux and Windows, with Docker or Podman.
- **Reproducible.** Base images pinned by digest, pi pinned by version,
  multi-arch (amd64 and arm64), built locally from source.

### What the container sees

| Path in the container | Source | Access |
|---|---|---|
| Your project, at the same path as on the host | current directory | read-write |
| `.git/hooks`, `.git/config` of the project | current directory | **read-only** |
| `/home/pi/.pi` (login, settings, sessions) | `~/.pi-docker` | read-write |
| `/home/pi`, `/tmp` | tmpfs, discarded after the run | read-write |
| Everything else | the image | **read-only** |
| Your home, `~/.ssh`, `~/.pi`, Docker socket, host variables | — | **not available** |

## Quick start

**Requirements:** Docker (Docker Desktop, OrbStack, Colima or Docker Engine)
or Podman. On macOS and Linux, bash; the macOS system bash 3.2 works. On
Windows, PowerShell 5.1 or 7.

```sh
# 1. Get the code and build the image
git clone https://github.com/just-me-dot-dev/pi-docker.git
cd pi-docker
bin/pi-docker --build

# 2. Log in once, from any project directory
cd ~/code/my-project
~/path/to/pi-docker/bin/pi-docker --login     # then run /login inside pi

# 3. Use it
~/path/to/pi-docker/bin/pi-docker
```

To type `pi-docker` (or just `pi`) instead of the full path, see
[Installation](#installation).

## Installation

Make the wrapper available in every terminal.

<details open>
<summary><b>zsh and bash</b> (macOS, Linux, WSL)</summary>

Add the `bin` directory to your `PATH` in `~/.zshrc` (zsh, the macOS default)
or `~/.bashrc` (bash):

```sh
# pi-docker: run pi in a hardened container
export PATH="$HOME/path/to/pi-docker/bin:$PATH"
```

Or link the script into a directory that is already on your `PATH`:

```sh
mkdir -p ~/.local/bin
ln -s "$PWD/bin/pi-docker" ~/.local/bin/pi-docker
```

To make the container your default `pi`, also add an alias:

```sh
alias pi='pi-docker'
```

Open a new terminal or run `source ~/.zshrc`. The alias shadows a pi
installed on the host; reach that one with `command pi`. Aliases only apply
to interactive shells, so scripts still call the real `pi`.

</details>

<details>
<summary><b>PowerShell</b> (Windows)</summary>

Open your profile with `notepad $PROFILE` (create it first with
`New-Item -Force $PROFILE` if it does not exist) and add:

```powershell
# pi-docker: run pi in a hardened container
function pi-docker { & "$HOME\path\to\pi-docker\bin\pi-docker.ps1" @args }

# Optional: make the container your default pi
function pi { pi-docker @args }
```

If Windows refuses to run scripts, allow local scripts for your user once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

</details>

## Usage

```text
pi-docker [wrapper options] [--] [pi arguments]
```

Wrapper options come first. Everything after them, or after `--`, is passed
to pi unchanged:

```sh
pi-docker                                  # interactive session
pi-docker -c                               # continue the last session here
pi-docker -p "summarize this repository"   # one-shot prompt
git diff | pi-docker -p "review this"      # pipe input
pi-docker -- --help                        # pi's own help
pi-docker --shell                          # bash in the container, for debugging
```

| Option | Description |
|---|---|
| `--build [args]` | Build the image. Extra arguments go to `docker build`. |
| `--login` | Publish the OAuth callback ports for this run. See [Authentication](#authentication). |
| `--shell` | Start `bash` in the container instead of pi. |
| `--mount-ro PATH` | Also mount `PATH` read-only, at the same path. Repeatable. |
| `--env NAME` | Pass the host variable `NAME` into the container. Repeatable. Skipped with a warning when it is not set. |
| `--unsafe-git` | Do not protect `.git/hooks` and `.git/config`. |
| `--help` | Show the wrapper help. |

> [!NOTE]
> PowerShell removes a bare `--` from the arguments. Quote it:
> `pi-docker '--' --help`.

## Configuration

The wrapper reads these environment variables:

| Variable | Default | Description |
|---|---|---|
| `PI_DOCKER_IMAGE` | `pi-docker:latest` | Image to run and to tag when building. |
| `PI_DOCKER_HOME` | `~/.pi-docker` | Host directory mounted as `~/.pi` in the container. |
| `PI_DOCKER_ENGINE` | auto | `docker` or `podman`. Docker is preferred when both exist. |
| `PI_DOCKER_USER` | auto | Value for `--user`. See [Platform support](#platform-support). |
| `PI_DOCKER_MEMORY` | `4g` | Memory limit. Includes data written to tmpfs. |
| `PI_DOCKER_PIDS` | `1024` | Limit on processes and threads. |
| `PI_DOCKER_CPUS` | none | CPU limit, for example `2`. |

Only a few host variables reach the container by default: `TERM`,
`COLORTERM`, `TERM_PROGRAM` and `TERM_PROGRAM_VERSION` for the terminal UI,
and your git `user.name` and `user.email` so commits are attributed to you.
Everything else needs `--env`.

## Authentication

### Browser login

Browser logins redirect to a callback server that pi starts on a fixed port.
`--login` publishes these ports for one run, bound to `127.0.0.1` only:

```sh
pi-docker --login                            # then /login inside pi
pi-docker --login -- auth login anthropic    # or log in without a session
```

pi prints the login URL; open it in the browser on your host. If the callback
does not arrive, paste the final redirect URL into pi. Providers that use
device codes, such as GitHub Copilot, need no ports at all.

Normal runs publish no ports, so several `pi-docker` sessions can run side by
side. The login is saved in `~/.pi-docker/agent/auth.json`.

### API keys

Store a key in the container's state directory:

```sh
pi-docker -- auth login anthropic --api-key
```

Or pass it from your host environment for a single run:

```sh
pi-docker --env ANTHROPIC_API_KEY
```

## Customization

### Settings, skills and prompts

The container has its own pi state directory, `~/.pi-docker/agent`, which is
separate from your host `~/.pi/agent`. Put the settings, skills and prompt
templates the containerized pi should use there.

To share a host directory without copying it, mount it read-only; it appears
at the same path. Then list that path in `~/.pi-docker/agent/settings.json`:

```sh
pi-docker --mount-ro ~/.agents/skills
```

```json
{ "skills": ["/Users/me/.agents/skills"] }
```

> [!WARNING]
> Never set `PI_DOCKER_HOME` to your host `~/.pi`. The agent could then write
> extensions or instructions that your host pi runs without a sandbox.

### pi version and updates

The image never updates itself. To change the pi version, rebuild:

```sh
pi-docker --build                                 # the pinned default version
pi-docker --build --build-arg PI_VERSION=1.6.1    # a specific version
pi-docker --build --no-cache                      # refresh all layers
```

Base images are pinned by digest in the [`Dockerfile`](Dockerfile), and
Dependabot proposes updates.

### Extending the image

The image ships pi, Node.js 24, npm, git, ripgrep, fd, curl, jq, less,
Python 3 and uv. For other tools, build on top of it and point
`PI_DOCKER_IMAGE` at the result:

```dockerfile
FROM pi-docker:latest
USER root
RUN apt-get update \
	&& apt-get install -y --no-install-recommends golang \
	&& rm -rf /var/lib/apt/lists/*
USER pi
```

```sh
docker build -t pi-docker:go .
PI_DOCKER_IMAGE=pi-docker:go pi-docker
```

## Privacy

pi sends prompts, code and sessions only to your model provider, unless you
share them yourself. It does make a few requests of its own. The image turns
off the ones that are not needed:

| Request | Data sent | Image default | Controlled by |
|---|---|---|---|
| Install report to `pi.dev` | pi version, OS, Node.js version, CPU architecture; once per pi version | **off** | `PI_TELEMETRY` |
| Attribution headers to OpenRouter, NVIDIA NIM and OpenCode | that the request comes from pi | **off** | `PI_TELEMETRY` |
| Version check at `pi.dev` | pi version, OS, Node.js version, CPU architecture | **off** | `PI_SKIP_VERSION_CHECK` |
| Model catalog refresh | the request itself | on | `PI_OFFLINE` |
| Analytics | experimental first-run setup only | off (opt-in) | `enableAnalytics` setting |

Turn the install report and attribution back on:

```sh
PI_TELEMETRY=1 pi-docker --env PI_TELEMETRY
```

Stop all automatic network activity, including model catalog refreshes and
pi package update checks. Model requests and logins still work:

```sh
PI_OFFLINE=1 pi-docker --env PI_OFFLINE
```

Also worth knowing:

- Every model request carries a User-Agent such as
  `pi/1.6.1 (linux; node/v24.22.3; arm64)`.
- pi stores a random `deviceId` in `~/.pi-docker/agent/settings.json`. It is
  sent only when you log in to OpenAI, as its agent host ID.
- `/share` uploads the whole session (to your Radius organization or as a
  private GitHub gist), and `/bug` uploads a report. Both run only when you
  call them. `/debug` writes `pi-debug.log` locally, including prompts and
  file contents.
- pi packages from npm or git are fetched from their registry and checked for
  updates on every start.

## Security

`pi-docker` limits the damage a misbehaving agent can do to the project you
started it in. It does **not** make the agent trustworthy. In particular:

- The agent can change or delete anything in the project directory.
- Files your tools later run on the host, such as `Makefile`, `package.json`
  scripts, `.envrc` or IDE tasks, are editable. Review changes before running
  them outside the container.
- Network access is unrestricted. The agent can upload project files and
  your pi credentials.

Read the full [threat model](docs/threat-model.md) before relying on
`pi-docker`. As extra safeguards, the wrapper refuses to start in `/` or in
your home directory, and never publishes ports except during `--login`.

## Platform support

| Platform | Wrapper | Notes |
|---|---|---|
| macOS (Docker Desktop, OrbStack, Colima) | `bin/pi-docker` | File ownership is mapped by the VM. |
| Linux (Docker Engine) | `bin/pi-docker` | Runs as your UID and GID, so new files belong to you. |
| Linux (Podman) | `bin/pi-docker` | Used when Docker is missing; runs with `--userns=keep-id`. |
| Linux (rootless Docker) | `bin/pi-docker` | Set `PI_DOCKER_USER=0:0`. This maps to your own user, but pi has root rights inside the container. Podman is the better choice. |
| Windows (Docker Desktop) | `bin/pi-docker.ps1` | `C:\code\app` appears as `/c/code/app`. Network shares cannot be mounted. |
| Windows (WSL) | `bin/pi-docker` | Behaves like Linux. |
| Windows (Git Bash) | `bin/pi-docker` | Works; use Windows Terminal rather than mintty for the terminal UI. |

Copying from pi uses OSC 52, so it reaches your host clipboard in terminals
that support it. Pasting images from the clipboard into pi does not work in
the container.

## Troubleshooting

<details>
<summary><code>image pi-docker:latest not found</code></summary>

Build the image first with `pi-docker --build`. With a custom
`PI_DOCKER_IMAGE`, build or pull that tag.
</details>

<details>
<summary><code>refusing to mount your home directory</code></summary>

`pi-docker` mounts the current directory. Mounting your home directory would
expose SSH keys and credentials, so it is refused. `cd` into a project first.
</details>

<details>
<summary><code>could not write config file .git/config: Device or resource busy</code></summary>

`.git/config` is read-only on purpose, so the agent cannot set hooks or
filters that run on your host. Run that `git config` or `git remote` command on
the host, or start with `--unsafe-git` if you accept the risk.
</details>

<details>
<summary>The login callback never arrives</summary>

Make sure you started with `--login`. If the port is taken, by another
`pi-docker --login` or by a CLI on the host, close it and retry. You can
always paste the final redirect URL from the browser into pi instead.
</details>

<details>
<summary>Builds or installs inside the container get killed</summary>

The container has a 4 GB memory limit, which includes files in `/tmp` and
`/home/pi`. Raise it, for example `PI_DOCKER_MEMORY=8g pi-docker`.
</details>

<details>
<summary>Windows: "running scripts is disabled on this system"</summary>

Allow local scripts for your user:
`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
</details>

## Development

```text
Dockerfile              hardened image
bin/pi-docker           wrapper for macOS, Linux, WSL and Git Bash
bin/pi-docker.ps1       wrapper for Windows PowerShell
tests/smoke.sh          checks the hardening against a built image
docs/threat-model.md    what is and is not protected
```

Run the smoke test after building the image:

```sh
bin/pi-docker --build && tests/smoke.sh
```

CI lints the scripts (shellcheck, hadolint, PSScriptAnalyzer), builds the
image natively on amd64 and arm64, runs the smoke test and scans the image
with Trivy. Changes are listed in the [changelog](CHANGELOG.md).

## License

[MIT](LICENSE). pi is a separate project ([pi.dev](https://pi.dev));
`pi-docker` is an independent wrapper and not affiliated with it.
