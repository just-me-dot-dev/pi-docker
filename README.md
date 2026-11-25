# pi-docker

Run [pi](https://pi.dev), the coding agent, in a hardened container.

pi runs shell commands on your behalf. `pi-docker` puts it in a box: it can
work on the project you started it in, and nothing else on your machine.

- pi runs as an **unprivileged user** with **all capabilities dropped** and
  `no-new-privileges`
- **read-only root filesystem**; only the project, `~/.pi` and two tmpfs
  mounts are writable
- **memory and process limits**
- only the **current directory** is mounted, plus a **separate pi state
  directory** (`~/.pi-docker`) that keeps your login across containers
- `.git/hooks` and `.git/config` are **read-only**, so the agent cannot plant
  code that git later runs on your host
- your host pi config (`~/.pi`) is **never mounted**
- works on **macOS, Linux and Windows** with **Docker or Podman**

Read [docs/threat-model.md](docs/threat-model.md) for what this protects and,
more importantly, what it does not.

## Requirements

- Docker (Docker Desktop, OrbStack, Colima, Docker Engine) or Podman
- macOS / Linux / WSL: bash (the macOS system bash 3.2 works)
- Windows: PowerShell 5.1 or 7

## Quick start

```sh
git clone https://github.com/just-me-dot-dev/pi-docker.git
cd pi-docker
bin/pi-docker --build                      # build the image locally

cd ~/code/my-project
/path/to/pi-docker/bin/pi-docker --login   # first run: use /login in pi
/path/to/pi-docker/bin/pi-docker           # every later run
```

The login is stored in `~/.pi-docker/agent/auth.json` and is shared by all
later containers.

## Make `pi-docker` available everywhere

### bash and zsh (macOS, Linux, WSL)

Put the `bin` directory on your `PATH`. Add this to `~/.zshrc` (zsh, the macOS
default) or `~/.bashrc` (bash), with the path of your clone:

```sh
# pi-docker: run pi in a hardened container
export PATH="$HOME/path/to/pi-docker/bin:$PATH"
```

Or link the script into a directory that is already on your `PATH`:

```sh
mkdir -p ~/.local/bin
ln -s "$PWD/bin/pi-docker" ~/.local/bin/pi-docker
```

Open a new terminal (or `source ~/.zshrc`) and run `pi-docker` in any
project.

To make the container your default `pi`, add an alias as well:

```sh
alias pi='pi-docker'
```

The alias shadows a pi installed on the host. Reach that one with
`command pi`. Aliases only work in interactive shells; scripts still call the
real `pi`.

### PowerShell (Windows)

Add a function to your PowerShell profile. `notepad $PROFILE` opens it
(create it first with `New-Item -Force $PROFILE` if it does not exist):

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

## Usage

```text
pi-docker [wrapper options] [--] [pi arguments]
```

Wrapper options come first. Everything after them is passed to pi unchanged:

```sh
pi-docker                        # interactive session in the current directory
pi-docker -c                     # continue the last session of this directory
pi-docker -p "summarize this repo"
git diff | pi-docker -p "review this change"
pi-docker -- --help              # pi's help; "--" ends the wrapper options
```

| Option | Effect |
|---|---|
| `--build [args]` | Build the image; extra args go to `docker build` |
| `--login` | Publish the OAuth callback ports for this run (see below) |
| `--shell` | Start `bash` in the container instead of pi |
| `--mount-ro PATH` | Also mount `PATH` read-only at the same path (repeatable) |
| `--env NAME` | Pass the host variable `NAME` into the container (repeatable) |
| `--unsafe-git` | Do not protect `.git/hooks` and `.git/config` |
| `--help` | Show the wrapper help |

| Variable | Default | Meaning |
|---|---|---|
| `PI_DOCKER_IMAGE` | `pi-docker:latest` | Image tag |
| `PI_DOCKER_HOME` | `~/.pi-docker` | Host directory mounted as `~/.pi` |
| `PI_DOCKER_ENGINE` | auto | `docker` or `podman` |
| `PI_DOCKER_USER` | auto | Value for `--user` |
| `PI_DOCKER_MEMORY` | `4g` | Memory limit (includes tmpfs usage) |
| `PI_DOCKER_PIDS` | `1024` | Process and thread limit |
| `PI_DOCKER_CPUS` | none | CPU limit, e.g. `2` |

> **PowerShell:** PowerShell drops a bare `--`. Quote it: `pi-docker '--' --help`.

### Logging in

Browser logins send you back to a callback server that pi starts on a fixed
port. `--login` publishes these ports **on the host loopback only**
(`127.0.0.1`), for one run:

```sh
pi-docker --login                         # then /login inside pi
pi-docker --login -- auth login anthropic # or log in without a session
```

pi prints the login URL; open it in your host browser. If the callback does
not arrive, paste the final redirect URL into pi; every provider supports
that. Providers with device codes (GitHub Copilot and others) need no ports.
Normal runs publish no ports, so several `pi-docker` sessions can run at once.

API keys work as well. Store one with `pi-docker -- auth login <provider>
--api-key`, or pass one per run with `pi-docker --env ANTHROPIC_API_KEY`.

### API keys and other variables

Nothing from your host environment reaches the container unless you name it
with `--env`. Only `TERM`, `COLORTERM`, `TERM_PROGRAM`, `TERM_PROGRAM_VERSION`
and your git identity (`user.name`, `user.email`) are passed by default.

### Sharing skills, prompts and extensions

The container uses its own state directory, `~/.pi-docker/agent`, not your
host `~/.pi/agent`. Put the skills, prompts and settings the containerised pi
should have there. To share a host directory read-only instead, mount it
(it appears at the same path) and list that path in
`~/.pi-docker/agent/settings.json`:

```sh
pi-docker --mount-ro ~/.agents/skills
```

```json
{ "skills": ["/Users/me/.agents/skills"] }
```

Do not point `PI_DOCKER_HOME` at your host `~/.pi`. The agent could then
write extensions or instructions that your host pi runs without a sandbox.

## Building

```sh
pi-docker --build                                  # default pi version
pi-docker --build --build-arg PI_VERSION=1.6.1     # a specific pi version
pi-docker --build --no-cache                       # refresh everything
```

The image never updates itself. To get a new pi release, rebuild. The base
images are pinned by digest in the `Dockerfile`; Dependabot proposes updates.

The image contains pi, Node.js, npm, git, ripgrep, fd, curl, jq, less, Python
3 and uv. Need more? Build your own image on top and point `PI_DOCKER_IMAGE` at
it:

```dockerfile
FROM pi-docker:latest
USER root
RUN apt-get update && apt-get install -y --no-install-recommends golang \
	&& rm -rf /var/lib/apt/lists/*
USER pi
```

## Platform notes

- **Linux (Docker Engine):** pi runs with your UID and GID, so files it
  creates belong to you.
- **Linux (rootless Docker):** set `PI_DOCKER_USER=0:0`. Container "root" is
  your own user there, but pi then has root rights inside the container.
  Prefer Podman.
- **Podman:** used automatically when Docker is missing, with
  `--userns=keep-id`.
- **macOS:** Docker Desktop, OrbStack and Colima map file ownership
  themselves.
- **Windows:** use `bin/pi-docker.ps1` from PowerShell, or `bin/pi-docker`
  from WSL. `C:\code\app` appears in the container as `/c/code/app`. Projects
  on network shares cannot be mounted. Git Bash works too, but use Windows
  Terminal rather than mintty for the TUI.
- Clipboard copies use OSC 52, so they reach your host clipboard when your
  terminal supports it. Pasting images from the clipboard does not work.

## Development

```sh
tests/smoke.sh    # checks the hardening against a built image
```

CI lints the scripts (shellcheck, hadolint, PSScriptAnalyzer), builds the
image on amd64 and arm64, runs the smoke test and scans the image with Trivy.

## License

[MIT](LICENSE)
