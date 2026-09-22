# Atelier

I sometimes use this repo (and dev container) as a "root directory" in which to clone any number of other repos for AI agents to work on while isolated in a containerized environment, locally or remotely.

Repos are meant to be cloned in the `bay` directory.

Tailscale and some harnesses come pre-installed, so once the `atelier` container is created/recreated, users only have to `sudo tailscale up`, start the harnesses of their choice to log in, and clone repos in `bay`. The container is then ready for isolated work through SSH, whether it is `tmux`, VSCode Agent Window, or any other ADE-type software.

![Atelier](docs/atelier.jpg)
