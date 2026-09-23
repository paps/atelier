#!/bin/bash
set -euo pipefail

# The service script elevates itself; keep the main command running as node.
/usr/local/share/atelier/start-services.sh
exec "$@"
