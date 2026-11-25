# Changelog

## v0.2.2

- link the blog post about pi-docker from the README

## v0.2.1

- restructure the README with features, installation, configuration,
  troubleshooting and platform sections

## v0.2.0

- turn off pi's install report and provider attribution headers by default
- document the requests pi makes on its own in a privacy section
- skip --env variables that are not set on the host, so they cannot remove
  image defaults

## v0.1.1

- stop dependabot from proposing non-LTS Node.js major versions

## v0.1.0

- add a hardened Dockerfile that installs pi as an unprivileged user
- add the `bin/pi-docker` wrapper for macOS, Linux, WSL and Git Bash
- add the `bin/pi-docker.ps1` wrapper for Windows PowerShell
- keep the pi login in a separate state directory shared by all containers
- publish the OAuth callback ports on the loopback with `--login`
- protect `.git/hooks` and `.git/config` from the agent
- add a smoke test, a threat model and a CI build with a vulnerability scan
- license the project under MIT
