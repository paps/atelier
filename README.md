# Atelier

This repo stores useful configuration for creating sandboxes for agents. I find that I generally only need about ~one sandbox per machine, into which any number of projects can be worked on simultaneously.

![Atelier](docs/atelier.jpg)

## Dev containers

When using a dev container, repos are meant to be cloned in the `bay` directory.

Tailscale and some harnesses come pre-installed, so once the container is created/recreated, users only have to `sudo tailscale up`, start the harnesses of their choice to log in, and clone repos in `bay`. The container is then ready for isolated work through SSH, whether it is `tmux`, VSCode Agents window, or any other ADE-type software.

## Docker Sandboxes

### Install and setup

Install from https://docs.docker.com/ai/sandboxes/install/

For Debian, install a `.deb` from https://github.com/docker/sbx-releases/releases (note: on Debian, `/usr/local/sbin:/usr/sbin:/sbin` need to be in `$PATH` to have `sbx daemon` work)

Release notes here: https://github.com/docker/sbx-releases/releases

Then run `sudo usermod -aG kvm $USER` and `newgrp kvm`

Then run the following (not root, not sudo):
```sh
sbx login

# Note: For Debian, it seems the daemon doesn't go in the background, which is also fine
sbx daemon start # or 'restart'

sbx policy init allow-all # Let's do that for now, might restrict more later
# Allow this for tailscale (see below)
sbx settings set platform.allowExperimentalFeatures true
sbx settings set feature.udp-egress true

sbx settings set ssh.agentForwardingEnabled false # By default, `sbx` forwards the host's SSH agent into sandboxes...

# Restart the daemon for good measure, to take into account settings changes above
sbx daemon restart # Note: For Debian / foreground daemon, stop and start it manually

sbx diagnostics
```

### Loading secrets

(`sbx` supports targeting a specific sandbox for secrets, but we'll just use global secrets for now)

The kit sets up git as the account of a stored GitHub secret, so store one before creating sandboxes: `sbx secret set github`. Give a Personal Access Token (PAT, classic) from a *different* user, for the agents to use. Typically needs the 'repo' and 'read:org' scopes, and eventually 'workflow' if there are GitHub Actions to manage.

Add a codex token through oauth: `sbx secret set openai --oauth`

Add a claude token: `sbx secret set anthropic`. This one doesn't support oauth, instead use `claude setup-token` on a logged in claude code and put the token you obtain as secret.

### Setting up a sandbox

```sh
sbx create --name SANDBOX_NAME --kit ./atelier-sbx-kit --publish 0.0.0.0:41643:41643/udp4 AGENT_NAME
sbx policy allow network --sandbox SANDBOX_NAME --protocol udp "**"
```

Replace `AGENT_NAME` with `codex` or `claude`.

Port forwarding with `--publish` and the UDP allow line are there to help Tailscale be efficient.

Then open an interactive shell with `sbx exec -it SANDBOX_NAME zsh`. Then run `sudo tailscale up` to make the sandbox join the tailnet, then simply ssh into the sandbox on port 2222.

### Mounting directories (optional)

```
# Mount a host directory at the same path inside the sandbox
sbx mount SANDBOX_NAME /home/paps/a-folder
# Or choose a destination inside the sandbox (read-write by default)
sbx mount SANDBOX_NAME /home/paps/a-folder:/workspace/data
# Or mount it read-only
sbx mount SANDBOX_NAME /home/paps/a-folder:/workspace/data:ro
```

```
# Undo the same-path mount
sbx umount SANDBOX_NAME /home/paps/a-folder
# Undo the custom-destination mount—including the read-only example
sbx umount SANDBOX_NAME /home/paps/a-folder:/workspace/data
```

### Updating the "boot script"

A sandbox keeps the copy of `setup.sh` made at creation and runs it on every start, so to update startup behavior, copy the new script in and restart the sandbox:

```sh
sbx cp atelier-sbx-kit/files/home/.local/share/atelier-sbx-kit/setup.sh SANDBOX_NAME:/home/agent/.local/share/atelier-sbx-kit/setup.sh
sbx stop SANDBOX_NAME
sbx exec -it SANDBOX_NAME zsh # or any other method of your choice to start the sandbox
```

Changes to `spec.yaml`, including its install step, still require recreating the sandbox.
