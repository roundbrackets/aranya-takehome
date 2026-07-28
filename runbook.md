# Runbook — build the cluster from scratch

This assumes you'll build the cluster from scratch using the configs in this dir.

## Assumptions

- Linux servers are up and have the requisite resources (recent Ubuntu is fine).
- They can reach each other on the private network.
- They are reachable via SSH from the internet.
- root can log in over SSH with a key, no password.
- They can reach the internet.
- Port 6443 is open on a host (you could make a tunnel, but let's not).
- Port 30080 is open to the internet for the web server.
- We have all of this
    - public IPs
    - private IPs
    - SSH key

## Notes

- Chose Calico over Cilium because of a Cilium `mount-cgroup` AppArmor issue on
  Ubuntu 24.04 (kubespray's pinned Cilium 1.19.3, no fix exposed).
- No kube-vip. The control plane is still replicated across three nodes with a three-member etcd cluster (quorum 2). The kubeconfig points at one public node IP, but it can be repointed to any of the three because all public IPs are included in the API certificate SANs.
- For when you mess it up:
  `uv run ansible-playbook -i inventory/aranya/hosts.yaml -u root --private-key <KEY> -b -e reset_confirmation=yes reset.yml`

## Step 1 — Kubespray + Python env (local, uv)

I like uv, but use whatever Python tool you prefer.

Pinned versions of kubespray, Argo CD, clusterdOS, etc. live in `versions.env`.

- set env vars with versions
- clone kubespray
- set up a Python virtualenv

```sh
# in aranya-takehome/
source versions.env
git clone --depth 1 -b "$KUBESPRAY_VERSION" https://github.com/kubernetes-sigs/kubespray.git kubespray

# in aranya-takehome/kubespray/
cd kubespray
uv venv --python 3.12 .venv && source .venv/bin/activate
uv pip install -r requirements.txt
```

## Step 2 — Kubespray inventory (overlay our config onto the sample)

Create an inventory from the default sample, then copy our files over it.

```sh
# in aranya-takehome/kubespray/
cp -rfp inventory/sample inventory/aranya
cp -rf ../inventory/aranya/. inventory/aranya/     # overlays hosts.yaml + group_vars
```

### kubespray Config changes

- `inventory/aranya/hosts.yaml`.
- `inventory/aranya/group_vars/k8s_cluster/k8s-cluster.yml`

Both files were copied from kubespray/inventory/sample and then modified.

**`inventory/aranya/group_vars/k8s_cluster/k8s-cluster.yml`**

```yaml
# CNI
kube_network_plugin: calico

# so the kubeconfig works over the interwebs for all IPs
supplementary_addresses_in_ssl_keys: >-
  {{ groups['kube_control_plane']
     | map('extract', hostvars, 'ansible_host')
     | list }}

# make sure we get a kubeconfig locally, pointing at the public IP
kubeconfig_localhost: true
kubeconfig_localhost_ansible_host: true
```

**`inventory/aranya/hosts.yaml`** — the IP addresses.

## Step 3 — Build the cluster

```sh
# in aranya-takehome/kubespray/
uv run ansible-playbook -i inventory/aranya/hosts.yaml -u root --private-key <KEY> -b cluster.yml
```

## Step 4 — Get kubeconfig, confirm the cluster is up

```sh
export KUBECONFIG="<path>/aranya-takehome/kubespray/inventory/aranya/artifacts/admin.conf"

kubectl get nodes    # expect aranya1, aranya2, aranya3 Ready
```

## Step 5 — Argo CD

- create the namespace
- apply the Argo CD install from GitHub
- wait for the rollout

```sh
# in aranya-takehome/
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
```

Make sure Argo is happy before moving on.

## Step 6 — clusterdOS (cert-manager, metrics-server, nfd, ksm)

Install ClusterdOS...

```sh
# in aranya-takehome/
kubectl apply -f manifests/clusterdos/install.yaml   # the finalizer warning is fine, ignore it
kubectl -n argocd get applications
kubectl wait --for=condition=Ready pod --all -n argocd --timeout=120s
```

Make sure the Argo applications are happy before moving on.

### metrics-server

Check it works — real numbers mean it's scraping:

```sh
$ kubectl top nodes
NAME      CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
aranya1   299m         8%       1597Mi          22%
aranya2   221m         6%       1607Mi          22%
aranya3   229m         6%       1376Mi          19%
```

### cert-manager

Check it's healthy 
— issue a self-signed cert
- confirm it goes Ready
- clean up

```sh
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: default
spec:
  secretName: test-cert-tls
  issuerRef: { name: selfsigned, kind: ClusterIssuer }
  dnsNames: [test.example.com]
EOF

# creates: clusterissuer 'selfsigned', cert 'test-cert' in default, secret 'test-cert-tls' in default
kubectl get certificate test-cert -n default     # READY -> True

# clean up
kubectl delete certificate test-cert -n default
kubectl delete clusterissuer selfsigned
kubectl delete secret test-cert-tls -n default
```

### clusterdOS config changes

- `aranya-takehome/manifests/clusterdos/install.yaml`
- Original copied from here: https://gitlab.com/aranya-tech/public/clusterdo

Set `clusterdos.clustername`

Enabled
- cert-manager
- metrics-server
- nfd
- ksm

In cert-manager section added
```
certmanager:
    enabled: true
    values:
        featureGates: "ExperimentalGatewayAPISupport=false"
        config:
            enableGatewayAPI: false
```            

clusterdOS turns on Gateway API support, but the Gateway CRDs aren't installed, so the controller crashes.

In metrics-server section added

```
metricsserver:
    enabled: true
    values:
        args: [--kubelet-insecure-tls]
```        

Enables insecure-tls to resolve issues.

## Step 7 — hello-aranya (public)

- Deploy the web server and query it.
- `aranya-takehome/manifests/hello-aranya/`
- aranya.gunnarsson.cc or any public IP
- port 30080

```sh
# in aranya-takehome/
kubectl apply -f manifests/hello-aranya/
curl -s http://aranya.gunnarsson.cc:30080   # renders "hello aranya" (RR DNS -> any node)
```

## Step 8 — validation

bash ./scripts/verify-requirements.sh

## Fixes 

For cilium, /opt/cni must be root:root

for kube_vip: it must be enabled and variables set. VIP interfaces must be provided and can be set in hosts.yaml 

## Notes

Linode enables cilium, kube_vip, and uses kubespray yo install argo amd adds clusterdos as a cluster app.

kubestrap_linode is a fork of kubespray because of the addition of clusterdos.
