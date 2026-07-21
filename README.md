# aranya-takehome

A from-scratch Kubernetes cluster built with [kubespray](https://github.com/kubernetes-sigs/kubespray), augmented with Argo CD + [clusterdOS](https://gitlab.com/aranya-tech/public/clusterdos), serving a public `hello aranya` page.

## What's here

| Path | Purpose |
|------|---------|
| `runbook.md` | **Start here.** Exact steps to build the cluster from three fresh nodes. |
| `versions.env` | Pinned versions (kubespray, Argo CD, clusterdOS). |
| `inventory/aranya/` | Kubespray inventory — `hosts.yaml` (IPs) + our `group_vars` overlay. |
| `manifests/clusterdos/install.yaml` | clusterdOS Argo CD Application (cert-manager, metrics-server, NFD, ksm enabled). |
| `manifests/hello-aranya/` | The public nginx demo (namespace, configmap, deployment, service). |
| `scripts/verify-requirements.sh` | Checks each take-home requirement, with truncated output. |

## Requirements

From the take-home:

1. Kubernetes from scratch with kubespray.
2. Argo CD.
3. clusterdOS with the cert-manager, metrics-server, and NFD gitapps, plus one extra of our choosing (kube-state-metrics).
4. A public nginx "hello aranya" page.
5. Admin kubeconfig shared via GPG to three recipients.
6. Code in a public repo (this one).

Preferences (encouraged, not required): private node network (done), Cilium over Calico (declined — see Decisions), no single point of failure (partial — see Decisions).

## Assumptions

- Three Ubuntu 24.04 nodes are up with adequate CPU/RAM/disk.
- root logs in over SSH with a key, no password.
- Nodes reach each other on the private network and can reach the internet.
- Ports 6443 (API) and 30080 (nginx) are open to the internet.

## Decisions

- **Calico, not Cilium.** kubespray's pinned Cilium 1.19.3 hits a `mount-cgroup` AppArmor failure on Ubuntu 24.04 with no exposed fix.
- **No kube-vip.** Internal control-plane HA already holds (3-node etcd quorum + kubespray's per-node localhost API load-balancer), and workloads span all three nodes. The admin kubeconfig points at one node IP (all three are in the cert SANs — repoint if a node dies).
- **NodePort, not LoadBalancer/Ingress.** No cloud LB, so a `LoadBalancer` Service would stay `Pending`; NodePort `30080` is provider-neutral.
- **metrics-server** runs with `--kubelet-insecure-tls` (kubelets serve self-signed certs).
- **cert-manager** has the Gateway API feature gate disabled (the Gateway CRDs aren't installed).
- **Argo CD** is the non-HA install — an Argo outage doesn't stop already-running pods.

## Topology

- Three nodes, each `control-plane` + `etcd` + `worker` (stacked HA). Calico CNI (kubespray default — see the runbook note on why not Cilium). Nodes talk over the private network. 
- The API certificates include all public control-plane IPs, allowing the kubeconfig to be repointed to any node if required.
- The nginx demo is reacheable via IP or round-robin DNS — `aranya.gunnarsson.cc`.
- Endpoint (API on `:6443`, nginx NodePort on `:30080`).

```
                           Public Internet
                                  │
                         aranya.gunnarsson.cc
                      round-robin DNS, 3 A records
                                  │
                         plain HTTP :30080
                                  │
              ┌───────────────────┼───────────────────┐
              │                   │                   │
      138.197.196.242     143.110.204.64      138.68.41.34
          aranya1            aranya2              aranya3
              │                   │                   │
              └────── Kubernetes NodePort :30080 ─-───┘
                                  │
                           Nginx service
                                  │
                           "Hello Aranya"


       ┌─────────────────────────────────────────────────────┐
       │                 Private node network                │
       │                                                     │
       │   aranya1             aranya2             aranya3   │
       │   control plane       control plane       control-  │
       │   etcd                etcd                plane     │
       │   worker              worker              etcd      │
       │                                           worker    │
       │                                                     │
       │                 Calico networking                   │
       └─────────────────────────────────────────────────────┘

Kubernetes API access:
    kubectl
       │
       ├── https://138.197.196.242:6443
       ├── https://143.110.204.64:6443
       └── https://138.68.41.34:6443

The kubeconfig uses one of the IP endpoints whose address is covered
by the Kubernetes API certificate.

No kube-vip or external API load balancer is configured.
``` 
