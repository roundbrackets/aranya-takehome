# Install plan

Execute top to bottom. Each step is a gate for the next. Minimal checks only —
just enough to know a step succeeded before moving on.

Assumptions: three Linode VMs are up, on a working VLAN, can reach each other and
the internet. SSH as `root` with the provided key.

## Inputs to fill once (then everything else is fixed)

| Node | Public IP (SSH) | VLAN private IP |
|------|-----------------|-----------------|
| node1 | `<PUB1>` | 10.20.0.11 |
| node2 | `<PUB2>` | 10.20.0.12 |
| node3 | `<PUB3>` | 10.20.0.13 |

- API VIP (kube-vip, unused VLAN addr): `10.20.0.10`
- VLAN interface name on the nodes: `<IFACE>` (e.g. `eth1` — confirm once: `ssh root@<PUB1> ip -br addr`)
- SSH key path: `<KEY>`

---

## Step 1 — Kubespray + Python env (local, uv)
```sh
cd aranya-takehome
source versions.env
git clone --depth 1 -b "$KUBESPRAY_VERSION" https://github.com/kubernetes-sigs/kubespray.git kubespray
cd kubespray
uv venv --python 3.12 .venv && source .venv/bin/activate
uv pip install -r requirements.txt
```

## Step 2 — Inventory (overlay our config onto the kubespray sample)
```sh
cp -rfp inventory/sample inventory/aranya
cp ../inventory/rehearsal/hosts.yaml inventory/aranya/hosts.yaml   # then fill <PUB*> IPs
```
Edit `inventory/aranya/group_vars/k8s_cluster/k8s-cluster.yml`:
```yaml
kube_network_plugin: cilium
supplementary_addresses_in_ssl_keys:      # so the emailed kubeconfig works over public IPs
  - <PUB1>
  - <PUB2>
  - <PUB3>
```
Edit `inventory/aranya/group_vars/all/all.yml`:
```yaml
kubeconfig_localhost: true                # drops admin.conf into inventory/aranya/artifacts/
# --- no-SPOF API endpoint via kube-vip (VLAN supports ARP; done in the same run) ---
kube_vip_enabled: true
kube_vip_controlplane_enabled: true
kube_vip_arp_enabled: true
kube_vip_address: 10.20.0.10
kube_vip_interface: <IFACE>
loadbalancer_apiserver:
  address: 10.20.0.10
  port: 6443
```
> If kube-vip misbehaves, remove that block and re-run — it's a preference, not a
> requirement. Keep kube-proxy (default). Do not enable any clusterdOS Cilium gitapp.

## Step 3 — Build the cluster
```sh
ansible-playbook -i inventory/aranya/hosts.yaml -u root --private-key <KEY> -b cluster.yml
```
(This is the long one. ~20–40 min.)

## Step 4 — Get kubeconfig, confirm cluster is up
```sh
export KUBECONFIG="$PWD/inventory/aranya/artifacts/admin.conf"
# point the kubeconfig at a reachable endpoint for later delivery:
#   server: https://10.20.0.10:6443  (VIP; reachable from a node/tunnel)
#   for reviewers, a public node IP is in the cert SANs — repoint as needed
kubectl get nodes -o wide        # GATE: all 3 Ready
```

## Step 5 — Argo CD
```sh
cd ..                            # back to aranya-takehome
kubectl create namespace argocd
kubectl apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s   # GATE
```

## Step 6 — clusterdOS (cert-manager, metrics-server, nfd, ksm)
```sh
kubectl apply -f manifests/clusterdos/install.yaml
kubectl -n argocd get applications   # GATE: children Synced + Healthy (give it a few min)
```

## Step 7 — hello-aranya (public)
```sh
kubectl apply -f manifests/hello-aranya/
curl -s http://<PUB1>:30080        # GATE: renders "hello aranya"
```

## Step 8 — Deliver admin kubeconfig (GPG)
```sh
# confirm server: in the kubeconfig is reachable by reviewers first
scripts/encrypt-kubeconfig.sh admin.conf <reviewer keys...>
```

## Step 9 — Publish
```sh
# secret-scan, then push aranya-takehome to GitHub (public)
```

---

## Then: repeat on the aranya nodes
Same steps with `inventory/production/hosts.yaml` (real IPs already filled) and a
free VLAN VIP (not `10.46.0.10` — that's aranya3). Confirm the VLAN interface name.
