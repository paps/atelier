#!/bin/bash
# Start Tailscale on each devcontainer start.
set -euo pipefail

if (( EUID != 0 )); then
	exec sudo -n bash "$0" "$@"
fi

command -v tailscaled tailscale >/dev/null
mkdir -p /var/lib/tailscale /run/tailscale

# Keep the daemon running after the lifecycle command exits.
if ! pgrep -x tailscaled >/dev/null; then
	nohup tailscaled --tun=userspace-networking \
		--state=/var/lib/tailscale/tailscaled.state \
		--socket=/run/tailscale/tailscaled.sock \
		--port=41642 \
		>>/var/log/tailscaled.log 2>&1 </dev/null &
fi

# JSON status succeeds even before login; wait for the daemon, not authentication.
for (( attempt = 0; attempt < 50; attempt++ )); do
	if tailscale --socket=/run/tailscale/tailscaled.sock status --json >/dev/null 2>&1; then
		printf 'Tailscale daemon is ready. To log in and enable SSH, run: sudo tailscale up --ssh\n'
		exit 0
	fi
	sleep 0.2
done

echo 'Tailscale daemon did not become ready. Check /var/log/tailscaled.log.' >&2
exit 1
