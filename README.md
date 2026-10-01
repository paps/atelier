# Atelier

This repo stores useful configuration for creating containers or sandboxes for agents. I find that I generally only need about ~one container or sandbox per machine, into which any number of projects can be worked on simultaneously.

Repos that we want to work on are meant to be cloned in the `bay` directory. This directory is then meant to be mounted onto the container or sandbox.

![Atelier](docs/atelier.jpg)

## Dev containers

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

sbx policy reset # Interactively configure network access. Just use 'Open' for now
# Allow this for tailscale (see below)
sbx settings set platform.allowExperimentalFeatures true
sbx settings set feature.udp-egress true

sbx settings set ssh.agentForwardingEnabled false # By default, `sbx` forwards the host's SSH agent into sandboxes...

# Restart the daemon for good measure, to take into account settings changes above
sbx daemon restart # Note: For Debian / foreground daemon, stop and start it manually

sbx diagnose
```

### Loading secrets

(`sbx` supports targeting a specific sandbox for secrets, but we'll just use global secrets for now)

The kit sets up git as the account of a stored GitHub secret, so store one before creating sandboxes: `sbx secret set github`. Give a Personal Access Token (PAT, classic) from a *different* user, for the agents to use. Typically needs the 'repo' and 'read:org' scopes, and eventually 'workflow' if there are GitHub Actions to manage.

Add a codex token through oauth: `sbx secret set openai --oauth`. If doing the oauth flow on a remote machine, do it in a SSH session with forwarding like so `ssh -o ExitOnForwardFailure=yes -L 1455:localhost:1455 user@server` so that the oauth callback can land properly (replace 1455 with whatever port you can observe being set in the callback URL)

Add a claude token: `sbx secret set anthropic`. This one doesn't support oauth, instead use `claude setup-token` on a logged in claude code and put the token you obtain as secret.

### Setting up a sandbox

```sh
sbx run --detached --name SANDBOX_NAME --kit ./atelier-sbx-kit --publish 0.0.0.0:41643:41643/udp4 AGENT_NAME
sbx policy allow network --sandbox SANDBOX_NAME --protocol udp "**"
```

Replace `AGENT_NAME` with `codex` or `claude` or another sandbox image name.

We use `sbx run --detached` instead of `sbx create` to prevent the sandbox from being automatically stopped when sbx detects no active session running in it.

Then open an interactive shell with `sbx exec -it SANDBOX_NAME zsh`. Then run `sudo tailscale up` to make the sandbox join the tailnet, then simply ssh into the sandbox on port 2222.

Port forwarding with `--publish` and the UDP allow line are there to help Tailscale be efficient. Verify that is it working with `tailscale ping SANDBOX_NAME` and confirming no DERP relay is used. Sometimes it takes a while to take effect, but after a few minutes direct access to the machine (no relay) can be achieved, I don't know why it does that.

### Finishing setup touches

```sh
sudo dpkg-reconfigure tzdata # set the desired timezone
sudo apt autoremove
sudo tailscale set --operator=$USER # let the non-root user manipulate tailscale freely
```

If the sandbox package manager provides outdated neovim, ask the agent the following: *"Remove outdated neovim and neovim-runtime apt packages in favor of a recent compatible .deb you can find in the neovim/neovim-releases official repository. Do a dry run pass first and wait for me to confirm before removal and install."*

Also, upgrade the agent harness you're using. It's not necesseraly up to date when freshly pulled from docker sandboxes images.

And choose a different color for tmux for the sandbox: `nvim ~/.tmux.local.conf` (use a variation of the two example lines at the end of [tmux.conf](https://github.com/paps/dotfiles/blob/master/tmux/tmux.conf))

### Mounting directories (optional, but recommended for `bay`)

```sh
# How to mount a directory:
sbx mount SANDBOX_NAME ~/atelier/bay:/home/agent/bay
# How to mount a read-only directory:
sbx mount SANDBOX_NAME ~/a-folder:/workspace/data:ro
```

```sh
# How to un-mount:
sbx umount SANDBOX_NAME ~/a-folder:/workspace/data:ro
```

### Updating the "boot script"

A sandbox keeps the copy of `setup.sh` made at creation and runs it on every start, so to update startup behavior, copy the new script in and restart the sandbox:

```sh
sbx cp atelier-sbx-kit/files/home/.local/share/atelier-sbx-kit/setup.sh SANDBOX_NAME:/home/agent/.local/share/atelier-sbx-kit/setup.sh
sbx stop SANDBOX_NAME
sbx exec -it SANDBOX_NAME zsh # or any other method of your choice to start the sandbox
```

Changes to `spec.yaml`, including its install step, still require recreating the sandbox.
