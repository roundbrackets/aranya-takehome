op[en ports!


# Install plan

Execute top to bottom. Each step is a gate for the next. Minimal checks only —
just enough to know a step succeeded before moving on.

Assumptions: three Linode VMs are up, on a working VLAN, can reach each other and
the internet. SSH as `root` with the provided key.

## Inputs to fill once (then everything else is fixed)

VLAN = `192.168.0.0/24`. Confirm each node's actual VLAN IP with `ip -br addr`.

| Node | Public IP (SSH) | VLAN private IP |
|------|-----------------|-----------------|
| node1 | `<PUB1>` | 192.168.0.11 |
| node2 | `<PUB2>` | 192.168.0.12 |
| node3 | `<PUB3>` | 192.168.0.13 |

- API VIP (kube-vip, unused VLAN addr): `192.168.0.10`
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
cp ../inventory/production/hosts.yaml inventory/aranya/hosts.yaml
cp ../inventory/production/k8s-cluster.yml inventory/aranya/group_vars/k8s_cluster/k8s-cluster.yml
```
List changes to files

Edit `inventory/aranya/group_vars/k8s_cluster/k8s-cluster.yml`:
```yaml
kube_network_plugin: cilium
# so the emailed kubeconfig works over public IPs
supplementary_addresses_in_ssl_keys: >-
  {{ groups['kube_control_plane'] | map('extract', hostvars, 'ansible_host') | list }}
kubeconfig_localhost: true                # drops admin.conf into inventory/aranya/artifacts/
kubeconfig_localhost_ansible_host: true
```
## Step 3 — Build the cluster
```sh
ansible-playbook -i inventory/aranya/hosts.yaml -u root --private-key <KEY> -b cluster.yml
```
(This is the long one. ~20–40 min.)

## Step 4 — Get kubeconfig, confirm cluster is up
```sh
export KUBECONFIG="$PWD/inventory/aranya/artifacts/admin.conf"
# point the kubeconfig at a reachable endpoint for later delivery:
#   server: https://192.168.0.10:6443  (VIP; reachable from a node/tunnel)
#   for reviewers, a public node IP is in the cert SANs — repoint as needed
kubectl get nodes -o wide        # GATE: all 3 Ready
```

## Step 5 — Argo CD
```sh
cd ..                            # back to aranya-takehome
kubectl create namespace argocd
X kubectl apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

# The CustomResourceDefinition "applicationsets.argoproj.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes

kubectl apply -n argocd --server-side --force-conflicts -f  "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s   # GATE
```

## Step 6 — clusterdOS (cert-manager, metrics-server, nfd, ksm)
```sh
kubectl apply -f manifests/clusterdos/install.yaml
kubectl -n argocd get applications   # GATE: children Synced + Healthy (give it a few min)
```

Warning: metadata.finalizers: "resources-finalizer.argocd.argoproj.io": prefer a domain-qualified finalizer name including a path (/) to avoid accidental conflicts with other finalizer writers

metrics-server stuck

$ k top nodes
error: Metrics API not available

server logs
Jul 20 23:01:06 node1 kubelet[18880]: I0720 23:01:06.058122   18880 ???:1] "http:
TLS handshake error from 192.168.0.2:49705: remote error: tls: bad certificate"
E0720 23:12:51.061418       1 scraper.go:149] "Failed to scrape node" err="Get \"https://192.168.0.1:10250/metrics/resource\": tls: failed to verify certificate: x509: cannot validate certificate for 192.168.0.1 because it doesn't contain any IP SANs" node="node1"

install.yaml
metricsserver:
    values:
        args: [--kubelet-insecure-tls]

Calico service-account missing
Error creating: pods "calico-node-" is forbidden: error looking up service account kube-system/calico-node: serviceaccount "calico-node" not
Nameserver klimit exceeded

cert-manager
clusterdos-certmanager-cert-manager-7b9b8fb959-4bd7r              0/1     CrashLoopBackOff   11 (4m30s ago)   35m
          message: back-off 5m0s restarting failed container=cert-manager-controller pod=clusterdos-certmanager-cert-manager-7b9b8fb959-4bd7r_clusterdos-cert-manager(8df1876d-9950-4d2d-9d21-7fcf06db1861)

E0720 23:25:21.508526       1 main.go:41] "error executing command" err="the Gateway API CRDs do not seem to be present, but ExperimentalGatewayAPISupport is set to true. Please install the gateway-api CRDs. (the server could not find the requested resource)" logger="cert-manager"          

 3           certmanager:
 2             enabled: true
 1             values:
 0               featureGates: "ExperimentalGatewayAPISupport=gfalse"
  1               config:
 0                 enableGatewayAPI: false

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

---

- For these instructions to work all your hosts need to be reachable via a public ip
- each need the same ssh key for root


