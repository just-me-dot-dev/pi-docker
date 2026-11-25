# syntax=docker/dockerfile:1

# Hardened image for the pi coding agent.
# Build it with `bin/pi-docker --build`. Run it only through the wrapper, which
# adds the runtime hardening (read-only root, dropped capabilities, limits).

# uv binaries, pinned by digest
FROM ghcr.io/astral-sh/uv:0.13.10@sha256:a3ea1357342c1a4bf9a0c53a3deb1b55379aefa037338d8113d5771efa01774f AS uv

# Node.js LTS on Debian trixie, pinned by digest
FROM node:24-trixie-slim@sha256:4d00acb4bcc42c454c4eb801526f7ad7f772ea3bd4fd168c5cc2e384abcbb9d4

# pi release to install, override with --build-arg PI_VERSION=x.y.z
ARG PI_VERSION=1.6.1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Tools the agent works with. pi uses the system rg and fdfind instead of
# downloading its own copies.
# hadolint ignore=DL3008
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		bash \
		ca-certificates \
		curl \
		fd-find \
		git \
		jq \
		less \
		procps \
		python3 \
		ripgrep \
	&& rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /uvx /usr/local/bin/

# Install pi globally as root, so the agent cannot modify its own code
RUN npm install --global --omit=dev "@earendil-works/pi-coding-agent@${PI_VERSION}" \
	&& npm cache clean --force \
	&& rm -rf /root/.npm /tmp/*

# Turn the stock "node" user (UID/GID 1000) into the unprivileged "pi" user
RUN usermod --login pi --home /home/pi --move-home node \
	&& groupmod --new-name pi node

# System-wide git defaults. The workspace is owned by the host user, so git
# must trust it. The identity is a fallback; the wrapper passes the host one.
RUN git config --system safe.directory '*' \
	&& git config --system user.name "pi-docker" \
	&& git config --system user.email "pi-docker@localhost"

# Remove setuid and setgid bits, so nothing can gain privileges
RUN find / -xdev -perm /6000 -type f -exec chmod a-s {} +

ENV HOME=/home/pi \
	LANG=C.UTF-8 \
	PI_SKIP_VERSION_CHECK=1 \
	PI_SELF_UPDATE_COMMAND="echo pi-docker: rebuild the image with pi-docker --build to update pi" \
	PI_CLIPBOARD_OSC52=1 \
	NO_UPDATE_NOTIFIER=1 \
	NPM_CONFIG_UPDATE_NOTIFIER=false

# Numeric, so runtimes can verify that the user is not root
USER 1000:1000
WORKDIR /home/pi

ENTRYPOINT ["pi"]
