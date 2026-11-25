#!/usr/bin/env bash
#
# Smoke test for the image and bin/pi-docker. Runs the wrapper in a throwaway
# git project and checks that the hardening is in place. Needs a built image.

set -euo pipefail

WRAPPER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/pi-docker"
WORK="$(mktemp -d)"
export PI_DOCKER_HOME="$WORK/state"
trap 'rm -rf "$WORK"' EXIT

fail() {
	# Print a failure and exit
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

in_container() {
	# Run a shell snippet in the container and print its output. The exit
	# status is ignored, because some checks expect the snippet to fail.
	printf '%s\n' "$1" | "$WRAPPER" --shell -s 2>&1 || true
}

# Create a throwaway project
mkdir -p "$WORK/project"
cd "$WORK/project"
git init -q
echo "hello" >README

# Check that pi starts
"$WRAPPER" -- --version | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+' || fail "pi --version"

# Check the runtime hardening
in_container 'id -u' | grep -qvx 0 || fail "runs as root"
in_container 'grep CapEff /proc/self/status' | grep -q '0000000000000000' || fail "capabilities"
in_container 'grep NoNewPrivs /proc/self/status' | grep -q '1' || fail "no-new-privileges"
in_container 'touch /usr/x' | grep -q 'Read-only' || fail "root filesystem writable"
in_container 'touch .git/hooks/x' | grep -q 'Read-only' || fail ".git/hooks writable"

# Check the privacy defaults
# shellcheck disable=SC2016 # Expands in the container
in_container 'echo "$PI_TELEMETRY"' | grep -qx '0' || fail "telemetry not disabled"

# Check that the workspace and the state directory are writable
in_container 'touch created && touch ~/.pi/agent/created' >/dev/null
[ -f "$WORK/project/created" ] || fail "workspace not writable"
[ -f "$PI_DOCKER_HOME/agent/created" ] || fail "state directory not writable"

echo "smoke test passed"
