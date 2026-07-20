#!/usr/bin/env bash
# Post-install validation. Run with KUBECONFIG pointing at the admin config.
#
# Usage: KUBECONFIG=./admin.conf PUBLIC_IP=<node-ip> scripts/validate.sh
set -uo pipefail

: "${KUBECONFIG:?set KUBECONFIG to the admin kubeconfig path}"

line() { printf '\n===== %s =====\n' "$1"; }

line "nodes";            kubectl get nodes -o wide
line "system pods";      kubectl get pods -A | grep -Ev 'Running|Completed' || echo "all Running/Completed"
line "etcd members";     kubectl get pods -n kube-system -l component=etcd -o name 2>/dev/null | wc -l
line "argo applications"; kubectl get applications -n argocd 2>/dev/null || echo "argocd not installed yet"
line "metrics (top)";    kubectl top nodes 2>/dev/null || echo "metrics API not ready yet"
line "nfd labels";       kubectl get nodes -o json | grep -o '"feature.node.kubernetes.io[^"]*"' | sort -u | head || echo "no NFD labels yet"

if [ -n "${PUBLIC_IP:-}" ]; then
  line "hello-aranya @ ${PUBLIC_IP}:30080"
  if curl -fsS -m 10 "http://${PUBLIC_IP}:30080" | grep -q "hello aranya"; then
    echo "OK: page renders 'hello aranya'"
  else
    echo "FAIL: 'hello aranya' not found"
  fi
else
  echo "(set PUBLIC_IP to also test the public nginx endpoint)"
fi
