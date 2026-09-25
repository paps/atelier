#!/bin/bash
# Sandbox setup for the atelier-sbx-kit Docker Sandboxes kit. The kit copies this
# file into each sandbox at creation, and spec.yaml runs it on every sandbox
# start, as root, in the background. Installation stays in spec.yaml.
#
# To apply changes to an existing sandbox, copy this file in with `sbx cp` and
# restart the sandbox. Keep startup idempotent: it runs on every start and
# replays on container restarts.
set -euo pipefail

setup_startup() {
	# Runs before sshd starts accepting logins.
	ssh_env_snapshot # ssh-env workaround

	# Start each daemon from its own background subshell, which becomes the
	# daemon, so one failing doesn't stop the other. Wait instead of exiting, so
	# the daemons stay children of a running startup task.
	start_sshd &
	start_tailscaled &
	wait
}

start_sshd() {
	pgrep -x sshd >/dev/null && return 0

	mkdir -p /run/sshd /etc/ssh/sshd_config.d
	cat > /etc/ssh/sshd_config.d/remote-access.conf <<-'CONFIG'
		# Keep port 22 available for optional Tailscale SSH.
		Port 2222
		PasswordAuthentication no
		PermitRootLogin no
		# Refuse agent and X11 forwarding, which expose the client to the sandbox.
		# Not a security boundary: the user is a sudoer and can re-enable
		# them. Disable forwarding on the connecting client instead
		# (ForwardAgent no, ForwardX11 no).
		AllowAgentForwarding no
		X11Forwarding no
	CONFIG

	# Initialize authorized keys only when the file is missing.
	if [ ! -f /home/agent/.ssh/authorized_keys ]; then
		keys_file=$(mktemp)
		trap 'rm -f "$keys_file"' EXIT
		curl --fail --silent --show-error --location --retry 2 --connect-timeout 10 --max-time 30 https://github.com/paps.keys -o "$keys_file"
		# -l: show key fingerprints (validates the download); -f: read this file.
		ssh-keygen -lf "$keys_file" >/dev/null
		agent_group=$(id -gn agent)
		install -d -m 0700 -o agent -g "$agent_group" /home/agent/.ssh
		install -m 0600 -o agent -g "$agent_group" "$keys_file" /home/agent/.ssh/authorized_keys
		rm -f "$keys_file"
		trap - EXIT
	fi

	# -A: generate any missing default SSH host keys; preserve existing ones.
	ssh-keygen -A

	# -D: stay in the foreground; -e: write logs to stderr instead of syslog.
	exec /usr/sbin/sshd -D -e
}

start_tailscaled() {
	pgrep -x tailscaled >/dev/null && return 0

	mkdir -p /run/tailscale
	install -d -m 0700 /var/lib/tailscale
	exec tailscaled --tun=userspace-networking --port=41643 --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock
}

# BEGIN ssh-env workaround
# Tricks to make SSH logins work for now, until sbx supports them. sbx gives its
# environment (proxy settings, credential sentinels, PATH) only to processes it
# starts, and Docker's template loads /etc/sandbox-persistent.sh only in bash.
# To remove, delete this section, the call marked "ssh-env workaround", and the
# matching block in spec.yaml's install step, which makes logins import the
# snapshot below.

# Snapshot the sandbox environment on every start, for SSH logins to import.
# PID 1 holds the container environment: proxy settings, CA paths, credential
# sentinels, and PATH. Skip variables each login sets for itself, and SSH agent
# sockets, which reach the host's agent.
ssh_env_snapshot() {
	env_file=$(mktemp /run/ssh-login-env.XXXXXX)
	trap 'rm -f "$env_file"' EXIT
	# Single-quote each value; close, escape, and reopen around embedded quotes.
	quote="'\\''"
	# -r: keep backslashes; -d '': read NUL-terminated entries.
	while IFS= read -r -d '' entry; do
		name=${entry%%=*}
		value=${entry#*=}
		case $name in
			HOME|USER|LOGNAME|SHELL|MAIL|TERM|PWD|OLDPWD|SHLVL|_|SSH_*) continue ;;
		esac
		[[ $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
		printf "export %s='%s'\n" "$name" "${value//\'/$quote}"
	done < /proc/1/environ > "$env_file"
	chmod 0644 "$env_file"
	mv -f "$env_file" /run/ssh-login-env.sh
	trap - EXIT
}
# END ssh-env workaround

setup_startup
