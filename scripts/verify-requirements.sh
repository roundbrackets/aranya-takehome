#!/usr/bin/env bash
# Verify each take-home requirement (email items 1-6). Read-only.
# Green = check passed (exit 0 + output), red = failed/empty. Output is truncated.
#
#   KUBECONFIG=... PUBLIC_IP=... scripts/verify-requirements.sh
set -u

cd "$(dirname "$0")/.."                      # repo root
INVENTORY="${INVENTORY:-kubespray/inventory/aranya/hosts.yaml}"
export KUBECONFIG="${KUBECONFIG:-$PWD/kubespray/inventory/aranya/artifacts/admin.conf}"
PUBLIC_IP="${PUBLIC_IP:-$(awk '/ansible_host:/{print $2; exit}' "$INVENTORY" 2>/dev/null)}"

MAX=${MAX:-15}                               # max output lines per check

# colors (only when writing to a terminal, and NO_COLOR unset)
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; RST=$'\033[0m'
else
  RED=; GREEN=; RST=
fi

run() {
  local title="$1" cmd="$2" out n rc color status
  out="$(eval "$cmd" 2>&1)"; rc=$?
  n=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
    color=$GREEN; status=PASS
  else
    color=$RED;   status=FAIL
  fi
  printf '\n%s[%s]%s %s\n' "$color" "$status" "$RST" "$title"
  printf '$ %s\n' "$cmd"
  printf '%s\n' "$out" | head -n "$MAX" | sed 's/^/  /'
  [ "$n" -gt "$MAX" ] && printf '  … (+%d more lines, %d total)\n' "$((n - MAX))" "$n"
}

echo "KUBECONFIG=$KUBECONFIG"
echo "PUBLIC_IP=$PUBLIC_IP"

echo; echo "════ REQ 1: Argo CD installed ════"
run "argocd workloads"        "kubectl get pods -n argocd -o wide"

echo; echo "════ REQ 2: clusterdOS + gitapps ════"
run "argo Applications"       "kubectl get applications -n argocd"
run "cert-manager pods"       "kubectl get pods -A | grep -i cert-manager"
run "metrics-server (top)"    "kubectl top nodes"
run "NFD feature labels"      "kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.labels}{\"\\n\"}{end}' | tr ',' '\\n' | grep feature.node.kubernetes.io | sort -u"
run "ksm (optional gitapp)"   "kubectl get pods -A | grep -i kube-state-metrics"

echo; echo "════ REQ 3: nginx 'hello aranya', public ════"
run "pods across nodes"       "kubectl get pods -n hello-aranya -o wide"
run "service (NodePort)"      "kubectl get svc -n hello-aranya"
run "public HTTP response"    "curl -s --max-time 10 http://${PUBLIC_IP}:30080"

echo; echo "════ REQ 4: runbook ════"
run "runbook.md head"         "head -n 20 runbook.md"

echo; echo "════ REQ 6: public repo ════"
run "git remote"              "git remote -v"
run "latest commit"           "git log --oneline -1"

echo; echo "════ additional cluster checks ════"
run "kubectl version"         "kubectl version"
run "cluster-info"            "kubectl cluster-info"
run "readyz"                  "kubectl get --raw='/readyz?verbose'"
run "livez"                   "kubectl get --raw='/livez?verbose'"
run "admin can-i *"           "kubectl auth can-i '*' '*' --all-namespaces"
