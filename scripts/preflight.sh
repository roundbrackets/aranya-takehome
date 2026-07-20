#!/usr/bin/env bash
# Thin preflight: confirm the nodes are reachable and have what kubespray needs.
# Not an exhaustive audit — just enough to catch the obvious blockers early.
#
# Usage: SSH_KEY=/path/to/key scripts/preflight.sh <ip1> <ip2> <ip3>
set -euo pipefail

SSH_KEY="${SSH_KEY:?set SSH_KEY to the private key path}"
SSH_USER="${SSH_USER:-root}"
SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

if [ "$#" -lt 1 ]; then
  echo "usage: SSH_KEY=... $0 <ip> [<ip> ...]" >&2
  exit 1
fi

for ip in "$@"; do
  echo "==================== $ip ===================="
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" bash -s <<'REMOTE'
    echo "- hostname : $(hostname)"
    echo "- os       : $(. /etc/os-release && echo "$PRETTY_NAME")"
    echo "- kernel   : $(uname -r)"
    echo "- cpus     : $(nproc)"
    echo "- memory   :"; free -h | sed 's/^/    /'
    echo "- disk /   :"; df -h / | sed 's/^/    /'
    echo "- swap     : $(swapon --show --noheadings || echo none)"
    echo "- addrs    :"; ip -br addr | sed 's/^/    /'
    echo -n "- internet : "; curl -fsS -m 10 -o /dev/null -w "%{http_code}\n" https://gitlab.com || echo "UNREACHABLE"
REMOTE
  echo
done

echo "Reminder: verify private-network reachability BETWEEN nodes (ping the private IPs)."
