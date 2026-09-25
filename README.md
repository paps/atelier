# Atelier

I sometimes use this repo (and dev container) as a "root directory" in which to clone any number of other repos for AI agents to work on while isolated in a containerized environment, locally or remotely.

When using the dev container, repos are meant to be cloned in the `bay` directory.

Tailscale and some harnesses come pre-installed, so once the `atelier` container is created/recreated, users only have to `sudo tailscale up`, start the harnesses of their choice to log in, and clone repos in `bay`. The container is then ready for isolated work through SSH, whether it is `tmux`, VSCode Agent Window, or any other ADE-type software.

![Atelier](docs/atelier.jpg)

## Docker Sandboxes on headless Linux

[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/install/) supports Ubuntu
24.04+ with KVM and membership in the `kvm` group; Docker Desktop and Docker Engine
are not required on the host. Checked against stable `sbx v0.45.1` on 2026-09-25.

For a headless host, sign in with a Docker access token through stdin:

```sh
sbx login
sbx policy init allow-all # One-time setup if no network preset is configured.
sbx settings set ssh.agentForwardingEnabled false
sbx daemon restart # Applies the agent forwarding setting.
sbx diagnostics
```

By default, `sbx` forwards the host's SSH agent into sandboxes, which lets any
process inside use the host's SSH keys. The setting above turns that off for all
sandboxes.

From this repository's root, create the VM without attaching:

```sh
sbx create --name atelier codex --kit ./atelier-sbx-kit
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
[`atelier-sbx-kit`](atelier-sbx-kit/spec.yaml) installs dotfiles, Tailscale, and
OpenSSH server at creation, in that order, then wires the sandbox environment
into zsh and SSH logins (see below). The dotfiles installer already updates
package lists. Startup work lives in one script,
[`setup.sh`](atelier-sbx-kit/files/home/.local/share/atelier-sbx-kit/setup.sh),
which the kit copies into the sandbox.
The kit does not declare network permissions; use the host's `allow-all` preset
and the UDP rule above for open outbound access. Explicit deny rules and organization policies
still take precedence; see
[Docker's network policy documentation](https://docs.docker.com/ai/sandboxes/governance/access-controls/local/).

On every sandbox start, the kit's single background startup task runs
`setup.sh` as root, which starts OpenSSH and Tailscale, skipping daemons that are
already running. It creates runtime directories and any missing SSH host
keys. Tailscale uses userspace networking
and stores its identity in `/var/lib/tailscale/tailscaled.state`, so login survives
restarts of the same sandbox. Authenticate once from its shell with
`sudo tailscale up`.

`setup.sh` also writes the SSH configuration. OpenSSH listens on port **2222**, with password authentication, root login, and
agent and X11 forwarding disabled, matching the devcontainer. The `agent` user
has passwordless sudo, so code inside the sandbox could re-enable forwarding;
disable it for this host in your SSH client configuration instead, with
`ForwardAgent no` and `ForwardX11 no`.

If `/home/agent/.ssh/authorized_keys` is missing, startup downloads the public
keys from `https://github.com/paps.keys` and installs them for the `agent` user.
Existing authorized keys are left intact. Both daemons send their output through
the sandbox's startup logging.

`sbx` gives its environment only to processes it starts: proxy settings, CA
bundle paths, credential sentinels that the host proxy swaps for real secrets,
and a `PATH` that includes Codex. OpenSSH starts each login with a clean
environment instead. Until `sbx` handles this, the kit works around it. Before
starting OpenSSH, `setup.sh` snapshots the container environment from
PID 1 into `/run/ssh-login-env.sh`, leaving out per-login variables and SSH agent
sockets. `/etc/sandbox-persistent.sh`, which Docker's template loads in bash,
imports the snapshot into logins that lack `SANDBOX_ID`; the kit also loads that
file from `/etc/zsh/zshenv`. SSH sessions, including `ssh host command`, then
match `sbx exec`. The snapshot is rewritten on every sandbox start. In both
`spec.yaml`'s install step and `setup.sh`, this workaround sits between
`BEGIN ssh-env workaround` and `END ssh-env workaround` comments, and the call to
it in `setup.sh` is marked `ssh-env workaround`.

The startup task starts the daemons but does not restart them if they crash. Remote access
routing still needs configuration; starting both daemons
alone does not complete remote access setup. Recreating the sandbox loses its
Tailscale identity and SSH host keys along with its other internal files.

Codex uses the host's stored OpenAI OAuth secret through the sandbox proxy.
If you haven't stored it yet, run `sbx secret set openai --oauth` on the host.
The local kit does not declare credentials or write Codex configuration.

Optionally validate the kit with `sbx kit validate ./atelier-sbx-kit`.
[Kits](https://docs.docker.com/ai/sandboxes/customize/kit-reference/) are
experimental. Applying kit changes requires recreating the sandbox; doing so
discards its installed state and any files stored inside it.

The exception is `setup.sh`. A sandbox keeps the copy of `setup.sh` made
at creation and runs it on every start, so to update startup behavior, copy the
new script in and restart the sandbox:

```sh
sbx cp atelier-sbx-kit/files/home/.local/share/atelier-sbx-kit/setup.sh \
	atelier:/home/agent/.local/share/atelier-sbx-kit/setup.sh
sbx stop atelier
sbx run --name atelier
```

Changes to `spec.yaml`, including its install step, still require recreating the
sandbox.
