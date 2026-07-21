# Runbook — build the cluster from scratch

> Status: **outline** — sections get filled with exact, copy-pasteable commands
> during the Linode rehearsal, then confirmed on the aranya nodes.

## 0. Assumptions & topology
- Three fresh Ubuntu 24.04 nodes, root SSH via the provided key.
- Each node: control-plane + etcd + worker. Cilium CNI. Private network between nodes.
- Versions pinned in `versions.env`.
- _TODO: network diagram, node table (public/private IPs, VIP)._

## 1. Local tools (control machine)
- `uv` (Python), `kubectl`, `helm`, `gpg`, `git`, `ssh`.
- _TODO: exact install/verify commands._

## 2. Preflight

NOTE: base install of recent ubuntu is fine

Confirm
- reachable via ssh
- ssh key for root same on all hosts
- hosts can talk to each other preferably via private network
- hosts can reach the internet
- has recommendad RAM/CPU/disk

## 3. Kubespray

- source version ip 
- clone kubespray
- 

```sh
source versions.env
git clone --depth 1 --branch "$KUBESPRAY_VERSION" https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
uv venv && source .venv/bin/activate
uv pip install -r requirements.txt
# overlay our inventory:
cp -r ../inventory/<rehearsal|production> inventory/aranya   # includes hosts.yaml + group_vars
ansible-playbook -i inventory/aranya/hosts.yaml --private-key <key> cluster.yml
```
- _TODO: exact group_vars, key path, become flags. Fetch admin.conf from a control-plane node._

## 4. Validate base cluster
- 3 nodes Ready, system pods healthy, 3 etcd members, CoreDNS resolves, Cilium healthy.

NOTE: opens public IP

## 5. Argo CD
```sh
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml
```
- _TODO: wait-for-healthy, initial admin password retrieval (do NOT commit)._

## 6. clusterdOS
```sh
# edit manifests/clusterdos/install.yaml: set clustername (already set), gitapps enabled
kubectl apply -f manifests/clusterdos/install.yaml
```
Wait for child Applications (cert-manager, metrics-server, nfd, ksm) to be Synced + Healthy.

## 7. hello-aranya
```sh
kubectl apply -f manifests/hello-aranya/
```
Reachable at `http://<any-node-public-ip>:30080`.

## 8. Validate everything
```sh
scripts/validate.sh
```

## 9. Deliver admin kubeconfig (GPG)
```sh
scripts/encrypt-kubeconfig.sh admin.conf reviewer-keys/*.asc
```
- Confirm the kubeconfig `server:` is reachable by reviewers before encrypting.

## 10. Teardown / clean rebuild
```sh
cd kubespray && ansible-playbook -i inventory/aranya/hosts.yaml reset.yml
```
Then repeat from §2 — the reproducibility proof.

## Known limitations & tradeoffs
- _TODO: kube-vip / no-SPOF outcome, external API endpoint choice, Argo non-HA rationale._
