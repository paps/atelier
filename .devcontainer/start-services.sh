#!/bin/bash
# Start Tailscale and OpenSSH on every container start.
set -euo pipefail

if (( EUID != 0 )); then
	exec sudo -n bash "$0" "$@"
fi

command -v tailscaled tailscale ssh-keygen >/dev/null
mkdir -p /var/lib/tailscale /run/tailscale /run/sshd

# openssh
# -------

# Initialize keys only when the authorized_keys file is missing.
if [[ ! -f /home/node/.ssh/authorized_keys ]]; then
	keys_file=$(mktemp)
	trap 'rm -f "$keys_file"' EXIT
	curl --fail --silent --show-error --location --retry 2 --connect-timeout 10 --max-time 30 \
		https://github.com/paps.keys -o "$keys_file"
	ssh-keygen -lf "$keys_file" >/dev/null
	node_group=$(id -gn node)
	install -d -m 0700 -o node -g "$node_group" /home/node/.ssh
	install -m 0600 -o node -g "$node_group" "$keys_file" /home/node/.ssh/authorized_keys
	rm -f "$keys_file"
	trap - EXIT
fi

# Host keys identify this SSH server to incoming clients. Generate missing keys only.
ssh-keygen -A
# Start the daemon, logging to container stderr.
/usr/sbin/sshd -e

# tailscale
# ---------

# Keep the daemon running after this startup script exits.
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
		printf 'Tailscale is ready; to log in, run: sudo tailscale up\n'
		exit 0
	fi
	sleep 0.2
done

echo 'Tailscale daemon did not become ready. Check /var/log/tailscaled.log.' >&2
exit 1
