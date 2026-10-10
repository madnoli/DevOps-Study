# DevOps-Study

A personal study repo for growing from a strong Linux/DevOps practitioner into an
L5 (staff-level) DevOps engineer across **AWS, Azure and general DevOps tooling**.

It has three parts:

| File | What it is |
|------|------------|
| [`L5-DevOps-Mastery-Roadmap.md`](L5-DevOps-Mastery-Roadmap.md) | The study plan: a layered roadmap with 7 phases, from cloud core up to architecture and leadership. |
| [`nginx-podip/`](nginx-podip/README.md) | Lab exercise: nginx load-balanced over 5 pods, with a page that shows which pod's IP served each request. |
| [`kindctl.sh`](kindctl.sh) | A hands-on lab: one Bash script that builds and runs three local Kubernetes clusters (`dev`, `stg`, `prod`) with [kind](https://kind.sigs.k8s.io/), so you can practise what the roadmap covers. |

---

## 1. The roadmap

The roadmap treats DevOps as a **stack of layers**. Each layer depends on the one
below it, so you can't skip ahead:

```
LAYER 5  Strategy        Architecture, cost, organisation   <- where L5 work happens
LAYER 4  Reliability     SRE, observability, DR
LAYER 3  Delivery        CI/CD, GitOps, release
LAYER 2  Orchestration   Kubernetes / EKS / AKS / OpenShift
LAYER 1  Infrastructure  IaC, networking, compute
LAYER 0  Foundations     Linux, Git, scripting
```

### Phases

| # | Phase | Main topics |
|---|-------|-------------|
| 1 | Cloud core | Compute, storage, networking on AWS and Azure side by side |
| 2 | Containers & orchestration | Kubernetes, EKS, AKS, OpenShift; operators, etcd internals |
| 3 | Infrastructure as Code | Terraform, Bicep, CloudFormation, Ansible |
| 4 | CI/CD & GitOps | Jenkins, GitHub Actions, Argo CD |
| 5 | Observability & reliability | Prometheus, Grafana, CloudWatch, Azure Monitor, SLOs |
| 6 | Security & secrets | Vault, IAM, Azure AD |
| 7 | L5 territory | Multi-region/multi-cloud, DR, chaos engineering, cost, leadership |

The roadmap also covers:
- **What L5 means:** designing systems, making cost and build-vs-buy calls, setting standards, debugging failures that span teams, and mentoring.
- **Where to spend your time:** go quickly through phases 1–3, then slow down on 5–7, where most of the growth toward L5 happens.
- **Practice tasks:** for example, drawing the layer pyramid from memory, and mapping a real production incident to the layer that broke.

Start by reading the roadmap from top to bottom. Then use the lab below for the Kubernetes, ingress and multi-environment hands-on work.

---

## 2. The lab: `kindctl.sh`

`kindctl.sh` manages three kind clusters on one Linux host. They model a
promotion pipeline: dev → stg → prod.

| Cluster | API port | HTTP ingress | HTTPS ingress | Workers | Pod CIDR | Service CIDR |
|---------|----------|--------------|---------------|---------|----------|--------------|
| `dev`   | 6443 | `localhost:8080` | 8443 | 1 | 10.10.0.0/16 | 10.110.0.0/16 |
| `stg`   | 6444 | `localhost:8081` | 8444 | 2 | 10.20.0.0/16 | 10.120.0.0/16 |
| `prod`  | 6445 | `localhost:8082` | 8445 | 2 | 10.30.0.0/16 | 10.130.0.0/16 |

How the clusters are built:
- **The API server listens on loopback only** (`127.0.0.1`), so it is never exposed to the network.
- **Each cluster gets its own pod and service CIDRs.** All three share one Docker bridge, and separate ranges keep cross-cluster routing possible later.
- **ingress-nginx is pinned to the control-plane node,** because only that node publishes host ports 80/443. The script labels the node, patches the controller's `nodeSelector`, and checks where the controller pod actually landed.
- **Workers carry labels** `env=<cluster>`, `tier=app` and `topology.kubernetes.io/zone=zone-a|zone-b`, which you can use to practise scheduling and topology spread.
- **Every command can be re-run safely.** Each one moves the system toward the desired state instead of assuming a fresh start.

### Requirements

- A Linux host on x86_64 or arm64. Docker install is supported for Debian/Ubuntu, RHEL/CentOS/Rocky/Alma/Fedora, and Amazon Linux.
- `curl`, and root/`sudo` for `bootstrap`, `docker`, `tune` and `tools`.
- Enough RAM for 8 kind nodes when all three clusters are running. Use `down` to free memory when you're not using them.

### Quick start

```bash
chmod +x kindctl.sh

# One shot on a fresh box: docker + sysctl tuning + CLI tools + all clusters
sudo ./kindctl.sh bootstrap

# Or step by step
sudo ./kindctl.sh docker     # install Docker Engine for the detected distro
sudo ./kindctl.sh tune       # raise inotify / ARP limits (persists in /etc/sysctl.d/99-kind.conf)
sudo ./kindctl.sh tools      # kubectl, kind, helm, oc, kubectx/kubens, jq, fzf + completions
./kindctl.sh up              # create clusters + ingress, then verify

# Prove ingress works end to end
./kindctl.sh smoke           # deploy nginx Deployment + Service + Ingress to each cluster
curl localhost:8080          # dev  -> nginx welcome page
./kindctl.sh smoke --clean   # remove the test app
```

### Command reference

| Command | Purpose |
|---------|---------|
| `bootstrap` | `docker` + `tune` + `tools` + `up` (needs root) |
| `init [--force] [cluster…]` | Generate `dev.yaml` / `stg.yaml` / `prod.yaml` kind configs from the tables in the script |
| `docker` | Install Docker Engine from Docker's official repo for the detected OS |
| `tune` | Write host sysctl settings: inotify watches/instances and ARP GC thresholds |
| `tools` | Install the newest kubectl, kind, helm, oc, kubectx/kubens, plus shell aliases and completions |
| `upgrade` | Update kind to the latest release. Its default node image updates with it. |
| `up [cluster…]` | Create the cluster(s) and install ingress, then run `verify` |
| `create [cluster…]` | Create the cluster only, without ingress |
| `ingress [cluster…]` | Install or repair ingress-nginx only |
| `down [cluster…]` | Stop the node containers but **keep their state**, to free RAM |
| `start [cluster…]` | Start stopped clusters again and wait until the nodes are Ready |
| `destroy [cluster…]` | Delete clusters permanently. Asks you to type `yes` first. |
| `status` | Show tool versions, clusters, node containers, nodes, memory and the biggest consumers |
| `verify [cluster…]` | Curl each cluster's HTTP ingress port and explain the response code |
| `smoke [--clean] [cluster…]` | Deploy (or remove) a test nginx app with an Ingress, then run `verify` |

Commands that take `[cluster…]` act on all three clusters when you name none.

Reading `verify` output:
- `404`: nginx is up, but no route exists yet. This is normal before `smoke`.
- `2xx`/`3xx`: a route is serving traffic.
- `000`: no response. The controller is down, or it is running on the wrong node.

### Configuration

Set these as environment variables:

| Variable | Default | Effect |
|----------|---------|--------|
| `NODE_IMAGE` | *(unset)* | When unset, the script uses the node image built into your kind binary. Set it to a pinned image such as `kindest/node:vX.Y.Z@sha256:…` to freeze all clusters on one Kubernetes version. |
| `SMOKE_APP` | `web` | Name used for the smoke-test Deployment, Service and Ingress |
| `SMOKE_IMAGE` | `nginx:alpine` | Image used for the smoke test |

To change ports, worker counts or CIDRs, edit the tables at the top of
`kindctl.sh`. Then regenerate the configs with `./kindctl.sh init --force`, and
recreate the clusters with `destroy` followed by `up`.

### Shell helpers installed by `tools`

`/etc/profile.d/kube-tools.sh` adds:
- **Aliases:** `k`, `kx` (kubectx), `kn` (kubens), `kgp`, `kgn`, `kga`.
- **One alias per cluster:** `kdev`, `kstg`, `kprod`. Each one names its context explicitly, so you can't apply to the wrong cluster by accident.
- **A prompt prefix** that shows the current kube context.

To use them, open a new shell or run `source /etc/profile.d/kube-tools.sh`.

> Note: `oc` works against kind for the standard verbs (`get`, `apply`, `logs`, …).
> OpenShift-only commands such as `oc new-app` or `oc get route` need a real
> OpenShift cluster and will fail on kind. That is expected.

### Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| Clusters fail to boot, or nodes keep going `NotReady` | The host's inotify limits are too low. Run `sudo ./kindctl.sh tune`. |
| `verify` shows `000` | The ingress controller isn't running, or it landed on a worker. Run `./kindctl.sh ingress <cluster>`. |
| `smoke` reports 404 straight after deploying | nginx hadn't reloaded its config yet. Wait a few seconds and run `./kindctl.sh verify` again. |
| Clusters still run the old Kubernetes version after `upgrade` | Clusters keep their original node image. Run `destroy`, then `up`. |
| Clusters don't respond after a reboot | Run `./kindctl.sh start` |

---

## Suggested way to use this repo

1. Read the roadmap and do its **practice tasks**.
2. Stand up the lab with `bootstrap` or `up`, then run `smoke` to confirm it works.
3. Use the three clusters to practise each phase: Helm charts, GitOps promotion from dev to stg to prod with Argo CD, observability stacks, policy and secrets tooling, and chaos experiments.
4. Use `down`/`start` to keep resources in check between study sessions.
