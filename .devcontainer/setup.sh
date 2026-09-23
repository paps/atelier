#!/bin/bash
set -euo pipefail

# git setup
# ---------
# Only handle git config locally. For codespaces, leave it to them.
if [[ "${CODESPACES:-}" != "true" ]]; then

	# leaving this commented here for now, will use later when I force traffic through an inspection proxy
	#sudo cp mitmproxy-ca-cert.pem /usr/local/share/ca-certificates/mitm.crt
	#sudo update-ca-certificates

	# Save the container's GitHub token so SSH sessions (including VS Code agents)
	# can authenticate even when they don't inherit GH_TOKEN. gh auth login refuses
	# to save credentials while a token environment variable is set, so pass the
	# token through stdin with --with-token and unset those variables only for gh.
	# The setup script keeps its environment. Credentials are stored for the current
	# user, in a plain text config file if no system credential store is available.
	printf '%s\n' "${GH_TOKEN:?GH_TOKEN must be set}" |
		env -u GH_TOKEN -u GITHUB_TOKEN \
		gh auth login --hostname github.com --git-protocol https --with-token

	# Use gh as a git credential helper, with the environment token or saved login.
	gh auth setup-git

	# Set our git name and email based on what GitHub returns
	# (works assuming we have a valid GH_TOKEN when this script runs)
	git config --global user.name "$(gh api user --jq '.name // .login')"
	git config --global user.email "$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')"

	# We're going to use HTTPS with a PAT token (through gh) instead of SSH keys
	# but we don't want to mess with the already configured repo remote
	# (which would affect the dev container's host).
	# So we use the git config trick below:
	git config --global url."https://github.com/".insteadOf git@github.com:
	git config --global --add url."https://github.com/".insteadOf ssh://git@github.com/

fi
