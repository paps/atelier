# Atelier

I sometimes use this repo (and dev container) as a "root directory" in which to clone any number of other repos for AI agents to work on while isolated in a containerized environment, locally or remotely.

When using the dev container, repos are meant to be cloned in the `bay` directory.

Tailscale and some harnesses come pre-installed, so once the `atelier` container is created/recreated, users only have to `sudo tailscale up`, start the harnesses of their choice to log in, and clone repos in `bay`. The container is then ready for isolated work through SSH, whether it is `tmux`, VSCode Agent Window, or any other ADE-type software.

![Atelier](docs/atelier.jpg)

## Docker Sandboxes on headless Linux

[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/install/) supports Ubuntu
24.04+ with KVM and membership in the `kvm` group; Docker Desktop and Docker Engine
are not required on the host. Checked against stable `sbx v0.45.1` on 2026-09-24.

For a headless host, sign in with a Docker access token through stdin:

```sh
sbx login
sbx policy init allow-all # One-time setup if no network preset is configured.
sbx diagnostics
```

From this repository's root, create the VM without attaching:

```sh
sbx create --name atelier codex --kit ./sbx-kit
```

For direct Tailscale connections, enable experimental outbound UDP and explicitly
allow it for this sandbox. In `sbx 0.45.1`, the `allow-all` preset above only
grants TCP; publishing a UDP port alone does not enable outbound UDP.

```sh
sbx settings set platform.allowExperimentalFeatures true
sbx settings set feature.udp-egress true
sbx policy allow network --sandbox atelier --protocol udp "**"
```

Then attach to Codex, or reconnect later:

```sh
sbx run --name atelier
```

For an interactive shell instead, use `sbx exec -it atelier zsh`.

No host workspace is mounted. Docker's built-in Codex sandbox manages Codex
installation and authentication. The local v2 mixin in
[`sbx-kit`](sbx-kit/spec.yaml) installs dotfiles, Tailscale, and OpenSSH
server, in that order. The dotfiles installer already updates package lists.
The kit does not declare network permissions; use the host's `allow-all` preset
and the UDP rule above for open outbound access. Explicit deny rules and organization policies
still take precedence; see
[Docker's network policy documentation](https://docs.docker.com/ai/sandboxes/governance/access-controls/local/).

The kit's `setup.startup` hooks start OpenSSH and Tailscale as root on every
sandbox start, skipping daemons that are already running. They create runtime
directories and any missing SSH host keys. Tailscale uses userspace networking
and stores its identity in `/var/lib/tailscale/tailscaled.state`, so login survives
restarts of the same sandbox. Authenticate once from its shell with
`sudo tailscale up`.

The startup scripts and SSH configuration are inline in `sbx-kit/spec.yaml`.
OpenSSH listens on port **2222**, with password authentication and root login
disabled, matching the devcontainer. If `/home/agent/.ssh/authorized_keys` is
missing, startup downloads the public keys from `https://github.com/paps.keys`
and installs them for the `agent` user. Existing authorized keys are left intact.
Both daemons send their output through the sandbox's startup logging.

These hooks start the daemons but do not restart them if they crash. Remote access
routing still needs configuration; starting both daemons
alone does not complete remote access setup. Recreating the sandbox loses its
Tailscale identity and SSH host keys along with its other internal files.

Codex uses the host's stored OpenAI OAuth secret through the sandbox proxy.
If you haven't stored it yet, run `sbx secret set openai --oauth` on the host.
The local kit does not declare credentials or write Codex configuration.

Optionally validate the kit with `sbx kit validate ./sbx-kit`.
[Kits](https://docs.docker.com/ai/sandboxes/customize/kit-reference/) are
experimental. Applying kit changes requires recreating the sandbox; doing so
discards its installed state and any files stored inside it.
