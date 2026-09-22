#!/bin/bash
# Start Tailscale on each devcontainer start and name it {HOST}-atelier
set -euo pipefail

if (( EUID != 0 )); then
	exec sudo -n bash "$0" "$@"
fi

command -v tailscaled tailscale >/dev/null
read -r host_hostname < "$(dirname "${BASH_SOURCE[0]}")/.host-hostname"
: "${host_hostname:?Host hostname is empty; rerun the devcontainer initializeCommand}"
tailscale_hostname="${host_hostname}-atelier"
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
		tailscale --socket=/run/tailscale/tailscaled.sock set --hostname="$tailscale_hostname"
		printf 'Tailscale daemon is ready. To log in and enable SSH, run: sudo tailscale up --ssh --hostname=%q\n' "$tailscale_hostname"
		exit 0
	fi
	sleep 0.2
done

echo 'Tailscale daemon did not become ready. Check /var/log/tailscaled.log.' >&2
exit 1
