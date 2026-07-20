# aranya-takehome

A from-scratch Kubernetes cluster built with [kubespray](https://github.com/kubernetes-sigs/kubespray),
made "prod-ready" with Argo CD + [clusterdOS](https://gitlab.com/aranya-tech/public/clusterdos),
serving a public `hello aranya` page.

## What's here

| Path | Purpose |
|------|---------|
| `runbook.md` | **Start here.** Exact steps to build the cluster from three fresh nodes. |
| `versions.env` | Pinned versions (kubespray, Argo CD, clusterdOS). |
| `inventory/rehearsal/` | Kubespray inventory for the Linode rehearsal environment. |
| `inventory/production/` | Kubespray inventory for the aranya nodes. |
| `manifests/clusterdos/install.yaml` | clusterdOS Argo CD Application (cert-manager, metrics-server, NFD, ksm enabled). |
| `manifests/hello-aranya/` | The public nginx demo (namespace, configmap, deployment, service). |
| `scripts/preflight.sh` | Thin node reachability / private-network / internet check. |
| `scripts/validate.sh` | Post-install health + public-endpoint checks. |
| `scripts/encrypt-kubeconfig.sh` | GPG-encrypt the admin kubeconfig to the three reviewers. |

## Topology

Three nodes, each `control-plane` + `etcd` + `worker` (stacked HA). Cilium CNI.
Nodes talk over the private network; the nginx demo is exposed on the public IPs.

## Reproduce

See `runbook.md`. High level:

```
scripts/preflight.sh            # sanity-check the nodes
# clone kubespray @ pinned tag, uv venv, run cluster.yml with our inventory
# install Argo CD @ pinned manifest
kubectl apply -f manifests/clusterdos/install.yaml
kubectl apply -f manifests/hello-aranya/
scripts/validate.sh
```

## Security note

No secrets live in this repo. The SSH private key, the admin kubeconfig, and any
API keys are gitignored and delivered out-of-band (kubeconfig via GPG — see the script).
