# The L5 DevOps Mastery Roadmap
### AWS + Azure + Generic DevOps — From Strong Linux User to Staff-Level Engineer

---

## 0. The Mental Model First

Before any tool list — here's the picture you should hold in your head for the entire journey.

```
                         ┌─────────────────────────────┐
                         │   LAYER 5: STRATEGY          │
                         │   (Architecture, Cost, Org)  │  ← L5 lives mostly HERE
                         ├─────────────────────────────┤
                         │   LAYER 4: RELIABILITY       │
                         │   (SRE, Observability, DR)   │
                         ├─────────────────────────────┤
                         │   LAYER 3: DELIVERY          │
                         │   (CI/CD, GitOps, Release)   │
                         ├─────────────────────────────┤
                         │   LAYER 2: ORCHESTRATION     │
                         │   (Kubernetes / EKS / AKS)   │
                         ├─────────────────────────────┤
                         │   LAYER 1: INFRASTRUCTURE    │
                         │   (IaC, Networking, Compute) │
                         ├─────────────────────────────┤
                         │   LAYER 0: FOUNDATIONS       │
                         │   (Linux ✅, Git, Scripting) │  ← you're already here
                         └─────────────────────────────┘
```

**Why this shape, not a flat checklist:** every layer *constrains* the layer above it. A Kubernetes cluster (Layer 2) is only as good as the network you built for it (Layer 1). A CI/CD pipeline (Layer 3) is only as trustworthy as the observability (Layer 4) that tells you it broke something. **Tradeoff:** this means you can't shortcut to Kubernetes without VPC/networking fluency first — it'll always feel shaky. The analogy: you can't build the 10th floor of a building by getting really good at drywall if the foundation (floors 1-3) is unpoured concrete.

You said you know Linux — so we start at Layer 0.5 and move fast through the early layers, spending most of your time in Layers 3-5, which is where L4→L5 engineers actually differentiate themselves.

**One-line summary:** DevOps mastery is layered, not flat — each layer must be load-bearing before you build the next.

---

## 1. What "L5" Actually Means (so you're aiming at the right target)

**Analogy:** Think of engineering levels like flight certifications.
- **L3 (mid-level):** You can fly the plane on autopilot and handle routine turbulence. You follow the runbook.
- **L4 (senior):** You can fly manually in bad weather. You *write* the runbook.
- **L5 (staff/principal):** You decide **which planes the airline should buy**, design the routes, and train the other pilots — while still being able to fly if needed.

Concretely, at L5 you're expected to:
1. **Design systems**, not just operate them (multi-region, multi-cloud, disaster recovery)
2. **Make build-vs-buy and cost tradeoff decisions** that save/cost the company real money
3. **Set standards** other engineers follow (paved roads, golden pipelines)
4. **Debug the un-debuggable** — cross-team, cross-cloud, distributed failures
5. **Mentor** — because your leverage isn't your own hands anymore, it's everyone else's hands

Keep this list pinned — every phase below is building toward one of these five.

---

## 2. The Roadmap — Phase by Phase

```
TIME →   0───────3mo───────8mo───────14mo──────20mo──────26mo──────32mo──────ONGOING→

Phase:   [1: Cloud][2: Containers][3: IaC][4: CI/CD][5: Observ.][6: Security][7: SRE/Arch]
         Core        & K8s          + GitOps  + Release  ability             + Chaos      → L5
AWS+Az   compute/    EKS/AKS/       Terraform Jenkins/  Prometheus/ Vault/   Multi-region
         net/storage OpenShift      Bicep/CFN GH Actions Grafana/    IAM      DR, cost,
                                    +Ansible  /ArgoCD    CloudWatch/ /Azure   leadership
                                                          Azure Mon  AD
```

You already told me you work daily with **OpenShift, EKS, CI/CD, and secrets management** at TIAA — so Phases 1-3 below will move quickly for you; treat them as a *gap-filling and formalizing* pass rather than a from-scratch learn. Phases 5-7 are where the real L5 growth will happen.

---

### Phase 1 — Cloud Core: Compute, Storage, Networking (parallel AWS/Azure)

**Why first:** Every other tool (Kubernetes, Terraform, CI/CD) is just automation *on top of* these primitives. If you don't deeply understand a VPC/VNet, you will forever be copy-pasting Terraform you don't understand.

**Analogy:** A cloud account is a plot of land. Compute (EC2/VM) is the house you build. Storage (S3/Blob) is your warehouse. Networking (VPC/VNet) is the roads, gates, and fences that control who can drive in and out.

**Rosetta Stone — learn concepts once, map both clouds:**

| Concept | AWS | Azure |
|---|---|---|
| Virtual network | VPC | VNet |
| Subnetting | Subnets + Route Tables | Subnets + Route Tables |
| Compute | EC2 | Virtual Machines |
| Object storage | S3 | Blob Storage |
| Identity | IAM | Azure AD (Entra ID) |
| Managed K8s | EKS | AKS |
| Serverless | Lambda | Functions |
| DNS | Route 53 | Azure DNS |
| Secrets | Secrets Manager / SSM Parameter Store | Key Vault |
| Load balancer | ALB/NLB | Application Gateway / LB |

```
        ┌─────────────────── VPC / VNet (10.0.0.0/16) ───────────────────┐
        │                                                                 │
        │   ┌──── Public Subnet ────┐        ┌──── Private Subnet ────┐  │
        │   │  10.0.1.0/24          │        │  10.0.2.0/24           │  │
        │   │                       │        │                        │  │
        │   │   [ Load Balancer ]   │        │   [ App Servers/Pods ] │  │
        │   │         │             │        │         │              │  │
        │   │         ▼             │        │         ▼              │  │
        │   │   [ NAT Gateway ]─────┼───────▶│   [ Database (RDS) ]   │  │
        │   │                       │        │                        │  │
        │   └───────────┬───────────┘        └────────────────────────┘  │
        │               │                                                 │
        └───────────────┼─────────────────────────────────────────────────┘
                         ▼
                 [ Internet Gateway ]
                         │
                      🌐 Internet
```

**Why this design (not "put everything public"):** the private subnet has **no direct internet route in** — only *out*, via NAT. Tradeoff: this adds latency and NAT Gateway cost, but it means an attacker who compromises your public load balancer still can't directly reach your database. This is "defense in depth" — the same principle a submarine uses with multiple sealed compartments: one breach doesn't sink the ship.

**Practice tasks:**
1. In both AWS and Azure free tier, build the exact diagram above by hand (console first, no IaC yet) — public + private subnet, NAT, and a VM in each. Verify the private VM has no public IP but *can* reach the internet via NAT.
2. Write out (in your own words, no AI) what happens step-by-step when a packet from your laptop reaches the private database VM — every hop, every gateway.

---

### Phase 2 — Containers & Orchestration (Kubernetes / EKS / AKS / OpenShift)

**Why now:** Once compute/network is solid, the next problem is: *"I have 200 microservices and 50 servers — who decides what runs where?"* That's the scheduling problem, and Kubernetes is the answer.

**Analogy:** Kubernetes is an airport's air traffic control. Individual planes (containers) don't decide their own gate — a control tower (the **control plane**) constantly matches available runways (**nodes**) to incoming flights (**pods**), reroutes when a runway closes (node failure → reschedule), and never lets two planes land in the same spot at the same time.

```
                     ┌───────────────────────────────────────┐
                     │            CONTROL PLANE               │
                     │  ┌─────────┐ ┌────────────┐ ┌───────┐ │
                     │  │   API    │ │  Scheduler │ │ etcd  │ │
                     │  │  Server  │ │            │ │(state)│ │
                     │  └────┬─────┘ └─────┬──────┘ └───────┘ │
                     └───────┼─────────────┼───────────────────┘
                              │             │  "put Pod X on Node 2"
             kubectl apply ──▶│             ▼
                              │      ┌──────────────┐
                              │      │  Controller   │  (reconciliation loop:
                              │      │  Manager      │   "actual state == desired?")
                              │      └──────────────┘
             ┌────────────────┼───────────────────────────────┐
             ▼                ▼                                ▼
      ┌─────────────┐  ┌─────────────┐                 ┌─────────────┐
      │   NODE 1     │  │   NODE 2     │                │   NODE 3     │
      │ ┌─────────┐ │  │ ┌─────────┐ │                │ ┌─────────┐ │
      │ │ Pod A   │ │  │ │ Pod X   │◀┼── scheduled here│ │ Pod C   │ │
      │ └─────────┘ │  │ └─────────┘ │                │ └─────────┘ │
      │  kubelet     │  │  kubelet     │                │  kubelet     │
      └─────────────┘  └─────────────┘                └─────────────┘
```

**The single most important idea in Kubernetes — the reconciliation loop:**

```
   You declare:  "I want 3 replicas of my app running"   (desired state)
                              │
                              ▼
        ┌──────────────────────────────────────────┐
        │   Controller constantly asks:              │
        │   "Is actual state == desired state?"       │
        └──────────────────────────────────────────┘
                 │ NO                    │ YES
                 ▼                       ▼
        Take corrective action      Do nothing, check again
        (start/kill pods)           in a few seconds
                 │                       │
                 └───────────┬───────────┘
                              ▼
                        (loop forever)
```

**Why Kubernetes over "just run more VMs" (the tradeoff):** self-healing and bin-packing efficiency come at the cost of **enormous complexity** — a K8s cluster has more moving parts than the app it's running. This is why L5 engineers treat "do we even need Kubernetes here?" as a real question, not a given. Rocket engineers ask the same thing about redundant systems — every extra system is also an extra failure mode.

**EKS/AKS/OpenShift are just "who manages the control plane for you":**
- **EKS** = AWS runs your control plane, you manage worker nodes (or use Fargate to skip that too)
- **AKS** = same idea on Azure
- **OpenShift** = Red Hat's opinionated Kubernetes distribution with built-in CI/CD, security policies (SCCs), and a longer support lifecycle — common in regulated enterprises (banks, insurers)

Since you already run OpenShift and EKS day-to-day, your Phase 2 goal isn't "learn Kubernetes" — it's **close specific gaps**: write a custom controller/operator, understand `etcd` internals, and get comfortable reading raw `kubectl get events` and `describe` output to diagnose scheduling failures without guessing.

**Practice tasks:**
1. Kill the `kube-scheduler` (or a node) in a test cluster and observe, second by second, how the reconciliation loop responds. Document the sequence of events.
2. Write a one-page comparison: "When would I choose EKS Fargate vs. self-managed OpenShift nodes for a workload?" — argue both sides with real cost and control tradeoffs.

---

### Phase 3 — Infrastructure as Code + Configuration

**Why now:** Once you know *what* a good VPC and cluster look like by hand, automate it — because a human clicking consoles doesn't scale past one engineer, and it isn't repeatable or auditable.

**Analogy:** IaC is an architectural blueprint vs. a contractor building a house from memory. The blueprint (Terraform/Bicep) can be reviewed before anyone lifts a hammer, reused for the house next door, and — crucially — diffed: "what changes if we move this wall?"

```
   git commit (blueprint change)
         │
         ▼
  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐
  │  terraform    │      │  terraform    │      │  terraform    │
  │  plan         │─────▶│  (shows DIFF) │─────▶│  apply        │
  │  (dry run)    │      │  + 2 -1 ~3    │      │  (executes)   │
  └──────────────┘      └──────────────┘      └──────┬───────┘
                                                        ▼
                                              ┌──────────────────┐
                                              │  State file        │
                                              │  (source of truth   │
                                              │   for what EXISTS)  │
                                              └──────────────────┘
```

**Why the "plan → diff → apply" flow matters (why before how):** without the dry-run diff, infrastructure changes are like performing surgery blindfolded. The plan step is the pre-flight checklist a pilot reads aloud before takeoff — it catches the mistake *before* it's expensive.

**Tools to map (generic-first, since Terraform is cloud-agnostic):**
- **Terraform** (multi-cloud, use this as your default)
- **CloudFormation / CDK** (AWS-native alternative)
- **Bicep / ARM templates** (Azure-native alternative)
- **Ansible** — configuration management *inside* the boxes (patching, installing packages) — different job from Terraform, which just provisions the boxes

**Practice tasks:**
1. Take the VPC you hand-built in Phase 1 and write it as Terraform. Run `terraform plan` before every `apply` and read the diff out loud to yourself like a checklist.
2. Deliberately introduce configuration drift (manually change a security group in the console) then run `terraform plan` again — observe how Terraform detects and reports the drift.

---

### Phase 4 — CI/CD & GitOps

**Why now:** With infra automated, the next bottleneck is *shipping application code* safely and fast.

**Analogy:** A CI/CD pipeline is an assembly line with quality gates — like a car factory where every unit passes through paint inspection, crash-test simulation, and a final checklist *before* it's allowed to leave the factory. GitOps takes this further: the factory floor **watches the blueprint repository itself**, and re-builds automatically the instant the blueprint changes — no human has to push the "build" button.

```
  DEVELOPER                    CI                          CD (GitOps)
  ──────────                ─────────                    ─────────────
  git push  ──────────▶  ┌───────────┐
                          │  Build     │
                          │  (compile) │
                          └─────┬─────┘
                                ▼
                          ┌───────────┐
                          │  Test      │──── FAIL ──▶ 🔴 stop, notify dev
                          │  (unit/int)│
                          └─────┬─────┘
                                ▼ PASS
                          ┌───────────┐
                          │  Scan      │──── FAIL ──▶ 🔴 stop (CVE found)
                          │ (SAST/SCA) │
                          └─────┬─────┘
                                ▼ PASS
                          ┌───────────┐
                          │  Push image│
                          │  to registry│
                          └─────┬─────┘
                                ▼
                    ┌───────────────────────┐        ┌────────────────┐
                    │ Update image tag in     │───────▶│  ArgoCD/Flux    │
                    │ Git manifests repo      │        │  detects change │
                    └───────────────────────┘        │  & syncs cluster │
                                                        └────────┬────────┘
                                                                 ▼
                                                          🚀 Deployed to K8s
```

**Why GitOps over "CI tool directly deploys" (the tradeoff):** direct-deploy is simpler but means your CI system needs cluster-admin credentials — a huge blast radius if compromised. GitOps means the cluster *pulls* changes rather than being *pushed to*, so credentials never leave the cluster, and Git becomes your single audit trail ("who approved this deploy?" → "check the PR"). The cost: an extra hop (manifest repo) and eventual-consistency lag instead of instant push.

**Practice tasks:**
1. Build a pipeline (GitHub Actions or Jenkins — pick one) with all four gates above for a toy app, and make one gate deliberately fail to confirm it actually blocks the pipeline.
2. Set up ArgoCD against a test cluster, point it at a Git repo, then manually edit a live Deployment with `kubectl edit` — watch ArgoCD detect the drift and revert it. This is the single best "aha" moment for understanding GitOps.

---

### Phase 5 — Observability & Reliability (SRE mindset begins here)

**Why now:** Now that you ship fast, the critical question becomes: **"How do you know when it's broken — before your customer tells you?"**

**Analogy:** Observability is a hospital patient hooked up to monitors. **Metrics** are the heart-rate number on the screen (is it trending wrong?). **Logs** are the nurse's detailed notes (what exactly happened at 3:14am?). **Traces** are the full path of a single blood cell through the whole body (where exactly did this one request slow down, across 12 microservices?).

```
     METRICS                    LOGS                       TRACES
  (the "what")              (the "why")               (the "where")
┌────────────────┐    ┌─────────────────────┐    ┌──────────────────────┐
│  CPU: 92% ▲     │    │ 03:14:02 ERROR       │    │ Request abc123        │
│  Latency: 2.1s  │    │  DB connection       │    │  → API Gateway  12ms  │
│  Error rate: 8% │    │  pool exhausted      │    │  → Auth Svc     45ms  │
│  (Prometheus/   │    │  (ELK/Loki/          │    │  → Order Svc  2100ms◀─┼── found it!
│   CloudWatch/   │    │   Azure Log          │    │  → Payment Svc  30ms  │
│   Azure Monitor)│    │   Analytics)         │    │  (Jaeger/X-Ray/       │
└────────────────┘    └─────────────────────┘    │   App Insights)        │
        │                        │                └──────────────────────┘
        └────────────┬───────────┘
                      ▼
              ┌───────────────┐
              │   Grafana      │   ← single pane of glass, alerts fire from here
              │  (dashboards + │
              │   alerting)    │
              └───────────────┘
```

**The core SRE concept — SLI / SLO / Error Budget:**

**Analogy:** If your SLO (Service Level Objective) is "99.9% uptime per month," that's like a monthly allowance of pocket money for *risk*. 99.9% allows ~43 minutes of downtime per month — that's your **error budget**. Spend it on a risky deploy on day 3, and you have almost none left for the rest of the month, so the team should slow down and stabilize. This turns "reliability" from a vague feeling into a **number you can budget against**, exactly like a finance team budgets money.

**Practice tasks:**
1. Instrument a toy app with Prometheus client libraries, build a Grafana dashboard with your own SLI (e.g., request success rate), and configure an alert that fires when it drops below 99%.
2. Calculate your own error budget for a fictional SLO of 99.95%/month, in minutes. Then simulate "spending" it by injecting synthetic errors and watching your budget dashboard drain.

---

### Phase 6 — Security & Secrets Management

**Why now, not earlier:** Security bolted on at the end is fragile — but security taught before you understand *what* you're protecting (network, containers, pipelines) is abstract and forgettable. Now every concept has something real to attach to.

**Analogy:** Secrets management is a bank vault with a time-locked, single-use key dispenser — instead of writing the vault combination on a sticky note taped to the teller's monitor (hardcoding a password in your `.yaml` file), the vault (Vault/Key Vault/Secrets Manager) hands out a **short-lived key** only to an authenticated requester, and that key expires automatically.

```
   App Pod                     Secrets Manager               
  ┌──────────┐   1. "I am     ┌──────────────────┐
  │          │──── pod-sa-────▶│  Verify identity   │
  │  needs    │    identity"   │  (IAM role / AAD)   │
  │  DB       │                └─────────┬──────────┘
  │  password │                          │ 2. authorized
  │          │◀──── 3. short-lived ──────┘
  │          │       credential (TTL: 15 min)
  └──────────┘
        │
        ▼ 4. credential auto-expires — even if leaked,
          it's useless in 15 minutes
```

**Why short-lived over static credentials (the tradeoff):** static secrets are simpler to set up but a leaked one is a standing open door until someone notices and rotates it. Dynamic/short-lived secrets add setup complexity and a dependency on the secrets service being available — but a leak self-heals. This is the "principle of least privilege, least time" — the same reason a hotel gives you a keycard that stops working the day you check out, instead of a permanent brass key.

**Practice tasks:**
1. Set up HashiCorp Vault (or AWS Secrets Manager + IAM roles for service accounts) and get a pod to fetch a DB credential dynamically, with no secret ever stored in a YAML file or environment variable literal.
2. Write an IAM policy (AWS) and an equivalent Azure RBAC role using least-privilege — start from zero permissions and add only what's needed to pass a specific test, one line at a time.

---

### Phase 7 — L5 Territory: Architecture, Multi-Region/Cloud, Chaos, Leadership

This is where the roadmap stops being "learn tool X" and becomes "make judgment calls."

**Analogy:** Earlier phases taught you to fly the plane. This phase teaches you to **design the airline's entire route network** — which cities need direct flights (multi-region), what happens if an airport shuts down (disaster recovery), and how to train the next 50 pilots (mentoring/standards).

```
                    ┌─────────────────────────────────────────┐
                    │        GLOBAL TRAFFIC MANAGER              │
                    │   (Route 53 / Azure Traffic Manager)       │
                    └──────────────┬──────────────────────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              ▼                     ▼                       ▼
      ┌───────────────┐    ┌───────────────┐      ┌───────────────┐
      │  Region: US-E   │    │  Region: EU-W  │      │  Region: AP-SE │
      │  (Active)       │    │  (Active)       │      │  (Standby/DR)   │
      │  EKS + RDS      │    │  AKS + Azure SQL│      │  EKS (cold)     │
      │  Multi-AZ       │    │  Zone-redundant │      │  restore < 1hr  │
      └───────────────┘    └───────────────┘      └───────────────┘
              │                     │                       ▲
              └─────────────────────┴───────────────────────┘
                     continuous cross-region data replication
```

**Key L5 disciplines to build here:**
1. **Chaos Engineering** — deliberately breaking production-like systems to find weaknesses before customers do (tools: Chaos Mesh, AWS Fault Injection Simulator, Azure Chaos Studio)
2. **Cost/FinOps** — reading a cloud bill like a P&L statement, right-sizing, spot/reserved instance strategy
3. **Multi-cloud/hybrid strategy** — knowing *when* multi-cloud is genuinely worth the complexity tax vs. when it's resume-driven development
4. **Writing RFCs/design docs** — the artifact that proves L5 thinking; if you can't write the tradeoffs down clearly, you haven't actually finished the design
5. **Mentoring** — pairing with juniors, running blameless postmortems, setting the "paved road" so the whole org doesn't reinvent your Phase 1-6 lessons badly

**Practice tasks:**
1. Write a one-page RFC: "Should we go multi-region active-active or active-passive for [a service you know]?" List at least 3 real tradeoffs (cost, complexity, RTO/RPO) and make a recommendation.
2. Pick one real incident from your own work history (or a public postmortem from a company engineering blog) and rewrite it as a **blameless postmortem**: timeline, root cause, contributing factors, and 3 concrete follow-up actions.

---

## 3. Given Your Existing Background — Where to Actually Spend Time

You're not starting at zero — you already operate OpenShift, EKS, CI/CD, and secrets management at TIAA, plus client infra work at IOCL. That changes the roadmap's *weighting*, not its shape:

```
  Phase 1 (Cloud Core)      ▓▓░░░░░░░░  fast pass — fill Azure gaps if AWS-heavier so far
  Phase 2 (Containers/K8s)  ▓▓▓░░░░░░░  fast pass — go DEEPER (operators, etcd internals)
  Phase 3 (IaC)             ▓▓▓░░░░░░░  fast pass — formalize what you do ad-hoc
  Phase 4 (CI/CD/GitOps)    ▓▓▓▓░░░░░░  moderate — push toward full GitOps if not there yet
  Phase 5 (Observability)   ▓▓▓▓▓▓▓░░░  SLOW DOWN HERE — highest L5 leverage
  Phase 6 (Security)        ▓▓▓▓▓▓░░░░  SLOW DOWN HERE — you already touch secrets mgmt
  Phase 7 (Architecture)    ▓▓▓▓▓▓▓▓▓░  THIS is the L5 gate — most of your growth is here
```

---

## One-Line Summary

**L5 mastery isn't about knowing more tools than everyone else — it's about being the person whose design decisions the whole team can trust without re-checking.**

## Practice Tasks (roadmap-level, do these first)

1. **This week:** Draw the Layer 0-5 pyramid from Section 1 from memory, on paper, no peeking — then explain out loud (to a rubber duck, a friend, anyone) why each layer depends on the one below it.
2. **This month:** Pick ONE production incident you've handled at TIAA or IOCL and map it onto the "which layer broke?" pyramid — was it infra, orchestration, delivery, or observability that actually failed? This single exercise will show you exactly which phase to prioritize first.
