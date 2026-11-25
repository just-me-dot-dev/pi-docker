# Changelog

## v0.1.0

- add a hardened Dockerfile that installs pi as an unprivileged user
- add the `bin/pi-docker` wrapper for macOS, Linux, WSL and Git Bash
- add the `bin/pi-docker.ps1` wrapper for Windows PowerShell
- keep the pi login in a separate state directory shared by all containers
- publish the OAuth callback ports on the loopback with `--login`
- protect `.git/hooks` and `.git/config` from the agent
- add a smoke test, a threat model and a CI build with a vulnerability scan
- license the project under MIT
