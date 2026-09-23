FROM mcr.microsoft.com/devcontainers/typescript-node

RUN echo 'cache bust 1'

USER node

RUN curl -fsSL 'https://raw.githubusercontent.com/paps/dotfiles/refs/heads/master/min-setup-via-curl.sh' | bash

RUN curl -fsSL https://claude.ai/install.sh | bash
RUN curl -fsSL https://chatgpt.com/codex/install.sh | bash
RUN curl -fsSL https://tailscale.com/install.sh | sh

USER root

# Remove host keys created during installation so each container generates its own.
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssh-server \
    && rm -f /etc/ssh/ssh_host_*

COPY sshd_config /etc/ssh/sshd_config.d/atelier.conf
COPY entrypoint.sh start-services.sh /usr/local/share/atelier/
RUN chmod 0755 /usr/local/share/atelier/entrypoint.sh /usr/local/share/atelier/start-services.sh

USER node

# QoL improvement, e.g. to land there when doing `podman exec -it ID zsh`
WORKDIR /workspaces/atelier

ENTRYPOINT ["/usr/local/share/atelier/entrypoint.sh"]
CMD ["sleep", "infinity"]
