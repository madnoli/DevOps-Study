#!/usr/bin/env bash
#
# kindctl - lifecycle manager for the dev/stg/prod kind cluster set.
#
#   ./kindctl.sh bootstrap         # docker + sysctl + tools + clusters (root)
#   ./kindctl.sh docker            # install docker engine for the detected OS
#   ./kindctl.sh tune              # host sysctl tuning (run once, needs sudo)
#   ./kindctl.sh tools             # kubectl, oc, helm, kubectx/kubens + completions
#   ./kindctl.sh upgrade           # install latest kind -> latest node image
#   ./kindctl.sh up                # create + ingress, all clusters (idempotent)
#   ./kindctl.sh up dev            # just one
#   ./kindctl.sh create stg        # cluster only, no ingress
#   ./kindctl.sh ingress prod      # install/repair ingress only
#   ./kindctl.sh down              # stop containers, KEEP state (frees RAM)
#   ./kindctl.sh start             # resume after down
#   ./kindctl.sh destroy dev       # delete permanently
#   ./kindctl.sh status
#   ./kindctl.sh verify            # curl every ingress endpoint
#
# Design note: every operation CONVERGES toward a desired state rather than
# assuming a fresh start. Re-running any command is always safe.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- configuration -----------------------------------------------------------

# Node image policy.
#
# Default (NODE_IMAGE unset): pass NO --image flag, so kind uses the default
# node image compiled into the installed kind binary. That image is the exact
# one tested against this kind release, digest included, so it is always
# correct and always current for your binary. Keeping it "latest" therefore
# means keeping kind itself current -> `./kindctl.sh upgrade`.
#
# There is deliberately no `kindest/node:latest` tag upstream; hardcoding a
# guessed version tag risks a digest/containerd mismatch with your binary.
#
# To FREEZE all clusters on one version (recommended once dev/stg/prod need to
# match each other), export an explicit image:
#   export NODE_IMAGE="kindest/node:v1.36.1@sha256:3489c767..."
NODE_IMAGE="${NODE_IMAGE:-}"

KIND_RELEASES_API="https://api.github.com/repos/kubernetes-sigs/kind/releases/latest"

ALL=(dev stg prod)

# cluster -> host port for HTTP ingress (must match extraPortMappings in *.yaml)
declare -A HTTP_PORT=( [dev]=8080 [stg]=8081 [prod]=8082 )

INGRESS_MANIFEST="https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml"

MIN_WATCHES=524288
MIN_INSTANCES=512

# --- output helpers ----------------------------------------------------------

if [[ -t 1 ]]; then
  C_BLU=$'\033[1;34m'; C_GRN=$'\033[1;32m'; C_YEL=$'\033[1;33m'
  C_RED=$'\033[1;31m'; C_OFF=$'\033[0m'
else
  C_BLU=""; C_GRN=""; C_YEL=""; C_RED=""; C_OFF=""
fi

log()  { printf '%s==>%s %s\n' "$C_BLU" "$C_OFF" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '%swarn%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
die()  { printf '%serr %s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

# Resolve the cluster list: explicit args, or all of them.
targets() {
  if (( $# > 0 )); then printf '%s\n' "$@"; else printf '%s\n' "${ALL[@]}"; fi
}

exists() { kind get clusters 2>/dev/null | grep -qx "$1"; }

# --- preflight ---------------------------------------------------------------

preflight() {
  command -v kind    >/dev/null || die "kind not found in PATH"
  command -v kubectl >/dev/null || die "kubectl not found in PATH"
  docker info >/dev/null 2>&1   || die "cannot reach docker daemon"

  local watches instances
  watches=$(sysctl -n fs.inotify.max_user_watches)
  instances=$(sysctl -n fs.inotify.max_user_instances)

  if (( watches < MIN_WATCHES || instances < MIN_INSTANCES )); then
    warn "inotify limits low (watches=$watches instances=$instances)"
    warn "multiple kind clusters will fail to boot systemd or flap NotReady"
    warn "run:  sudo $0 tune"
    return 1
  fi
  return 0
}

# --- host tuning -------------------------------------------------------------

tune() {
  [[ $EUID -eq 0 ]] || die "tune needs root: sudo $0 tune"

  log "writing /etc/sysctl.d/99-kind.conf"
  tee /etc/sysctl.d/99-kind.conf >/dev/null <<'EOF'
# Raised for running multiple kind clusters on one host.
# Each kind node runs systemd + journald + containerd + kubelet, all of
# which consume inotify watches and instances from a per-UID pool.
fs.inotify.max_user_watches   = 1048576
fs.inotify.max_user_instances = 8192

# ARP table headroom for many container IPs on the docker bridge.
net.ipv4.neigh.default.gc_thresh1 = 4096
net.ipv4.neigh.default.gc_thresh2 = 8192
net.ipv4.neigh.default.gc_thresh3 = 16384
EOF

  sysctl --system >/dev/null
  ok "watches=$(sysctl -n fs.inotify.max_user_watches) instances=$(sysctl -n fs.inotify.max_user_instances)"
  ok "persists across reboot"
}

# --- create ------------------------------------------------------------------

create_one() {
  local name="$1"
  local cfg="$HERE/${name}.yaml"

  [[ -f "$cfg" ]] || die "config not found: $cfg"

  if exists "$name"; then
    ok "cluster '$name' already exists"
    return 0
  fi

  local -a img_args=()
  if [[ -n "$NODE_IMAGE" ]]; then
    img_args=(--image "$NODE_IMAGE")
    log "creating cluster '$name' (pinned image: $NODE_IMAGE)"
  else
    log "creating cluster '$name' (kind default image, $(kind version | head -1))"
  fi

  kind create cluster \
    --config "$cfg" \
    "${img_args[@]}" \
    --wait 180s

  local ver
  ver=$(kubectl --context "kind-${name}" get nodes \
          -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' 2>/dev/null || echo "?")
  ok "cluster '$name' created (kubernetes $ver)"
}

# --- ingress -----------------------------------------------------------------

ingress_one() {
  local name="$1"
  local ctx="kind-${name}"
  local cp="${name}-control-plane"

  exists "$name" || { warn "cluster '$name' does not exist, skipping ingress"; return 0; }

  # The controller must run on the node that owns the extraPortMappings,
  # because it binds hostPort 80/443 on whichever node it lands on.
  log "[$name] ensuring ingress-ready label on $cp"
  kubectl --context "$ctx" label node "$cp" ingress-ready=true --overwrite >/dev/null

  log "[$name] applying ingress-nginx"
  kubectl --context "$ctx" apply -f "$INGRESS_MANIFEST" >/dev/null

  # The upstream manifest does not always carry the nodeSelector, so the
  # scheduler is free to place the controller on a worker with no port
  # mapping -> connection reset on the host port. Pin it explicitly.
  log "[$name] pinning controller to control-plane"
  kubectl --context "$ctx" -n ingress-nginx patch deployment ingress-nginx-controller \
    --type=strategic \
    -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/os":"linux","ingress-ready":"true"}}}}}' \
    >/dev/null

  log "[$name] waiting for rollout"
  kubectl --context "$ctx" -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=180s

  local node
  node=$(kubectl --context "$ctx" -n ingress-nginx get pods \
           -l app.kubernetes.io/component=controller \
           -o jsonpath='{.items[0].spec.nodeName}')
  [[ "$node" == "$cp" ]] \
    && ok "[$name] controller on $node" \
    || warn "[$name] controller on $node (expected $cp) - host port will not work"
}

# --- lifecycle ---------------------------------------------------------------

cmd_create()  { preflight || die "fix preflight first"; while read -r c; do create_one "$c"; done < <(targets "$@"); }
cmd_ingress() { while read -r c; do ingress_one "$c"; done < <(targets "$@"); }

cmd_up() {
  preflight || die "fix preflight first"
  while read -r c; do
    create_one  "$c"
    ingress_one "$c"
  done < <(targets "$@")
  echo; cmd_verify "$@"
}

cmd_down() {
  while read -r c; do
    exists "$c" || { warn "cluster '$c' does not exist"; continue; }
    local ids
    ids=$(docker ps -q --filter "label=io.x-k8s.kind.cluster=$c")
    if [[ -z "$ids" ]]; then ok "[$c] already stopped"; continue; fi
    log "[$c] stopping nodes (state preserved)"
    docker stop $ids >/dev/null
    ok "[$c] stopped"
  done < <(targets "$@")
}

cmd_start() {
  while read -r c; do
    exists "$c" || { warn "cluster '$c' does not exist"; continue; }
    local ids
    ids=$(docker ps -aq --filter "label=io.x-k8s.kind.cluster=$c")
    [[ -n "$ids" ]] || { warn "[$c] no containers found"; continue; }
    log "[$c] starting nodes"
    docker start $ids >/dev/null
    # etcd needs a moment to elect and the apiserver to accept connections.
    log "[$c] waiting for nodes to become Ready"
    kubectl --context "kind-${c}" wait --for=condition=Ready nodes --all --timeout=180s >/dev/null \
      && ok "[$c] ready" \
      || warn "[$c] nodes not ready yet - check: kubectl --context kind-$c get nodes"
  done < <(targets "$@")
}

cmd_destroy() {
  local list; list=$(targets "$@")
  echo "About to PERMANENTLY DELETE:"; echo "$list" | sed 's/^/  - /'
  read -r -p "Type 'yes' to confirm: " reply
  [[ "$reply" == "yes" ]] || { warn "aborted"; return 1; }
  while read -r c; do
    log "deleting cluster '$c'"
    kind delete cluster --name "$c" || true
  done <<< "$list"
}

# --- keeping kind (and therefore the node image) current ---------------------

cmd_upgrade() {
  detect_env

  local current latest
  current=$(kind version 2>/dev/null | awk '{print $2}' || true)
  [[ -n "$current" ]] || current="none"

  log "querying latest kind release"
  latest=$(latest_kind_tag)

  echo "  installed: $current"
  echo "  latest:    ${latest:-unknown (API unreachable)}"

  if [[ -n "$latest" && "$current" == "$latest" ]]; then
    ok "already on the latest kind; node image is current"
    return 0
  fi

  install_kind || die "upgrade failed"

  warn "existing clusters still run their original node image."
  warn "recreate them to pick up the new one:  $0 destroy && $0 up"
}

# --- docker engine -----------------------------------------------------------

OS_ID=""; OS_LIKE=""; OS_VER=""; OS_CODENAME=""; OS_FAMILY=""

detect_os() {
  [[ -r /etc/os-release ]] || die "cannot read /etc/os-release"
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_LIKE="${ID_LIKE:-}"
  OS_VER="${VERSION_ID:-}"
  OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"

  case "$OS_ID" in
    ubuntu|debian|linuxmint|pop|raspbian)      OS_FAMILY=debian ;;
    rhel|centos|rocky|almalinux|ol|fedora)     OS_FAMILY=rhel   ;;
    amzn)                                      OS_FAMILY=amazon ;;
    sles|opensuse*)                            OS_FAMILY=suse   ;;
    *)
      case " $OS_LIKE " in
        *debian*) OS_FAMILY=debian ;;
        *rhel*|*fedora*|*centos*) OS_FAMILY=rhel ;;
        *suse*)   OS_FAMILY=suse ;;
        *)        OS_FAMILY=unknown ;;
      esac
      ;;
  esac
}

docker_apt() {
  # Docker's own repo, not Ubuntu's docker.io package - the distro package
  # lags badly and ships without the compose/buildx plugins.
  local repo_os="$OS_ID" key
  # Derivatives have no Docker repo of their own; map them to their base.
  case "$OS_ID" in
    linuxmint|pop) repo_os=ubuntu ;;
    raspbian)      repo_os=debian ;;
  esac
  [[ -n "$OS_CODENAME" ]] || die "cannot determine distro codename"

  log "prerequisites"
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq ca-certificates curl gnupg lsb-release

  log "adding docker apt repository ($repo_os / $OS_CODENAME)"
  $SUDO install -m 0755 -d /etc/apt/keyrings
  key=$(mktemp)
  # Download, then dearmor - not piped, for the same SIGPIPE reason as above.
  curl -fsSLo "$key" "https://download.docker.com/linux/${repo_os}/gpg" \
    || { rm -f "$key"; die "could not fetch docker gpg key"; }
  $SUDO gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg "$key"
  $SUDO chmod a+r /etc/apt/keyrings/docker.gpg
  rm -f "$key"

  echo "deb [arch=${ARCH_GO} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${repo_os} ${OS_CODENAME} stable" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null

  log "installing docker engine"
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

docker_rhel() {
  local mgr repo_os="$OS_ID"
  command -v dnf >/dev/null && mgr=dnf || mgr=yum
  case "$OS_ID" in
    centos|rocky|almalinux|ol) repo_os=centos ;;
    rhel)                      repo_os=rhel   ;;
    fedora)                    repo_os=fedora ;;
  esac

  log "adding docker repository ($repo_os)"
  $SUDO $mgr install -y -q dnf-plugins-core 2>/dev/null || $SUDO $mgr install -y -q yum-utils
  if command -v dnf >/dev/null; then
    $SUDO dnf config-manager --add-repo "https://download.docker.com/linux/${repo_os}/docker-ce.repo" 2>/dev/null \
      || $SUDO dnf config-manager addrepo --from-repofile="https://download.docker.com/linux/${repo_os}/docker-ce.repo"
  else
    $SUDO yum-config-manager --add-repo "https://download.docker.com/linux/${repo_os}/docker-ce.repo"
  fi

  log "installing docker engine"
  $SUDO $mgr install -y -q \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

docker_amazon() {
  # Amazon Linux has no docker-ce repo; use the vendored package.
  log "installing docker (amazon linux ${OS_VER})"
  if command -v dnf >/dev/null; then          # AL2023+
    $SUDO dnf install -y -q docker
  else                                         # AL2
    $SUDO amazon-linux-extras install -y docker
  fi
  warn "compose/buildx plugins are not bundled on Amazon Linux"
}

docker_postinstall() {
  log "enabling docker service"
  $SUDO systemctl enable --now docker 2>/dev/null \
    || warn "systemd not managing docker (container host?) - start it manually"

  # Log rotation. kind nodes are long-lived and chatty; without this a
  # single json-file log can grow until it fills the disk.
  if [[ ! -f /etc/docker/daemon.json ]]; then
    log "configuring log rotation"
    $SUDO mkdir -p /etc/docker
    $SUDO tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
EOF
    $SUDO systemctl restart docker 2>/dev/null || true
  else
    ok "  /etc/docker/daemon.json exists, left alone"
  fi

  # Let the invoking non-root user drive docker without sudo.
  local target="${SUDO_USER:-}"
  [[ -z "$target" && $EUID -ne 0 ]] && target="$USER"
  if [[ -n "$target" && "$target" != "root" ]]; then
    $SUDO usermod -aG docker "$target"
    warn "added '$target' to the docker group - log out and back in to take effect"
    warn "(docker group membership is root-equivalent; fine on a lab box, think twice on shared hosts)"
  fi
}

cmd_docker() {
  detect_env
  detect_os

  log "detected: ${PRETTY_NAME:-$OS_ID $OS_VER} [family=$OS_FAMILY arch=$ARCH_GO]"

  if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
    ok "docker already installed and running"
    docker version --format '  client {{.Client.Version}} / server {{.Server.Version}}' 2>/dev/null || true
    docker_postinstall
    return 0
  fi

  case "$OS_FAMILY" in
    debian) docker_apt    ;;
    rhel)   docker_rhel   ;;
    amazon) docker_amazon ;;
    suse)   die "SLES/openSUSE: install docker with 'zypper install docker', then re-run" ;;
    *)      die "unsupported distro '$OS_ID' - see https://docs.docker.com/engine/install/" ;;
  esac

  docker_postinstall

  if docker info >/dev/null 2>&1; then
    ok "docker ready: $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
  else
    warn "docker installed but not reachable yet - try: sudo systemctl start docker"
  fi
}

# --- toolchain ---------------------------------------------------------------

ARCH_GO=""   # amd64 | arm64      (kubectl, helm, kind naming)
ARCH_ALT=""  # x86_64 | arm64     (kubectx/kubens naming)
SUDO=""

detect_env() {
  case "$(uname -m)" in
    x86_64)  ARCH_GO=amd64; ARCH_ALT=x86_64 ;;
    aarch64) ARCH_GO=arm64; ARCH_ALT=arm64  ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
  [[ $EUID -eq 0 ]] && SUDO="" || SUDO="sudo"
  command -v curl >/dev/null || die "curl required"
}

# Install a downloaded file to /usr/local/bin with the right mode.
put_bin() { $SUDO install -m 0755 "$1" "/usr/local/bin/$2"; }

# Write a bash completion file from a command that emits one on stdout.
put_completion() {
  local name="$1"; shift
  "$@" 2>/dev/null | $SUDO tee "/etc/bash_completion.d/${name}" >/dev/null \
    && ok "  completion: $name" \
    || warn "  completion failed: $name"
}

install_kubectl() {
  local ver tmp
  ver=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
  log "kubectl $ver"
  tmp=$(mktemp)
  curl -fsSLo "$tmp" "https://dl.k8s.io/release/${ver}/bin/linux/${ARCH_GO}/kubectl" \
    || { rm -f "$tmp"; warn "kubectl download failed"; return 1; }
  put_bin "$tmp" kubectl; rm -f "$tmp"
  ok "  $(kubectl version --client 2>/dev/null | head -1)"
}

install_helm() {
  local ver tmp dir
  ver=$(curl -fsSL https://get.helm.sh/helm-latest-version)
  log "helm $ver"
  tmp=$(mktemp); dir=$(mktemp -d)
  curl -fsSLo "$tmp" "https://get.helm.sh/helm-${ver}-linux-${ARCH_GO}.tar.gz" \
    || { rm -rf "$tmp" "$dir"; warn "helm download failed"; return 1; }
  tar -xzf "$tmp" -C "$dir"
  put_bin "${dir}/linux-${ARCH_GO}/helm" helm
  rm -rf "$tmp" "$dir"
  ok "  $(helm version --short 2>/dev/null)"
}

install_oc() {
  # OpenShift CLI. Works as a kubectl superset against any conformant cluster,
  # so `oc get/apply/describe/logs` all work on kind. OpenShift-only verbs
  # (oc new-app, oc get route, oc adm) need the OpenShift API and will fail
  # here - that is expected, not a broken install.
  local tar url dir
  url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz"
  [[ "$ARCH_GO" == "arm64" ]] && \
    url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux-arm64.tar.gz"

  log "oc (OpenShift CLI, stable)"
  tar=$(mktemp); dir=$(mktemp -d)
  curl -fsSLo "$tar" "$url" \
    || { rm -rf "$tar" "$dir"; warn "oc download failed"; return 1; }
  # Extract only oc - the tarball also ships a kubectl we do not want to
  # clobber, since it lags the upstream release.
  tar -xzf "$tar" -C "$dir" oc 2>/dev/null || tar -xzf "$tar" -C "$dir"
  [[ -f "${dir}/oc" ]] || { rm -rf "$tar" "$dir"; warn "oc not found in tarball"; return 1; }
  put_bin "${dir}/oc" oc
  rm -rf "$tar" "$dir"
  ok "  $(oc version --client 2>/dev/null | head -1)"
}

# Resolve the newest kind tag. Returns empty string if GitHub is unreachable.
# NOTE: the JSON is captured into a variable BEFORE parsing. Piping curl into
# `grep -m1` closes the pipe early, curl dies with SIGPIPE (exit 23), and
# pipefail aborts the script. Download first, parse second.
latest_kind_tag() {
  local json=""
  json=$(curl -fsSL --max-time 15 "$KIND_RELEASES_API" 2>/dev/null) || return 0
  [[ -n "$json" ]] || return 0
  # Split on commas first: with compact JSON a greedy `.*` would match the
  # LAST "tag_name" in the payload rather than the release's own.
  printf '%s' "$json" | tr ',' '\n' \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1
}

install_kind() {
  local latest url tmp
  latest=$(latest_kind_tag)

  if [[ -n "$latest" ]]; then
    url="https://kind.sigs.k8s.io/dl/${latest}/kind-linux-${ARCH_GO}"
    log "kind ${latest}"
  else
    # Fallback: kind publishes a stable /dl/latest/ path, so a blocked or
    # rate-limited GitHub API is not fatal.
    url="https://kind.sigs.k8s.io/dl/latest/kind-linux-${ARCH_GO}"
    warn "GitHub API unavailable - falling back to /dl/latest/"
    log "kind (latest)"
  fi

  tmp=$(mktemp)
  curl -fsSLo "$tmp" "$url" || { rm -f "$tmp"; warn "kind download failed"; return 1; }
  put_bin "$tmp" kind; rm -f "$tmp"
  ok "  $(kind version 2>/dev/null | head -1)"
}

install_kubectx() {
  # The upstream bash implementations - no fzf dependency required, though
  # installing fzf turns `kubectx`/`kubens` with no args into a fuzzy picker.
  local base="https://raw.githubusercontent.com/ahmetb/kubectx/master"
  local tmp
  log "kubectx + kubens"
  for t in kubectx kubens; do
    tmp=$(mktemp)
    curl -fsSLo "$tmp" "${base}/${t}" \
      || { rm -f "$tmp"; warn "$t download failed"; continue; }
    put_bin "$tmp" "$t"; rm -f "$tmp"
  done

  for t in kubectx kubens; do
    curl -fsSL "${base}/completion/${t}.bash" \
      | $SUDO tee "/etc/bash_completion.d/${t}" >/dev/null \
      && ok "  completion: $t" || warn "  completion failed: $t"
  done
  ok "  $(kubectx --version 2>/dev/null || echo installed)"
}

install_shell_extras() {
  log "shell integration"

  # bash-completion provides the /etc/bash_completion.d loader itself.
  if ! dpkg -s bash-completion >/dev/null 2>&1; then
    $SUDO apt-get update -qq && $SUDO apt-get install -y -qq bash-completion
  fi
  $SUDO apt-get install -y -qq jq fzf >/dev/null 2>&1 || warn "  jq/fzf install skipped"

  $SUDO mkdir -p /etc/bash_completion.d

  command -v kubectl >/dev/null && put_completion kubectl kubectl completion bash
  command -v helm    >/dev/null && put_completion helm    helm    completion bash
  command -v oc      >/dev/null && put_completion oc      oc      completion bash
  command -v kind    >/dev/null && put_completion kind    kind    completion bash

  # Aliases + completion wiring for every login shell on the box.
  $SUDO tee /etc/profile.d/kube-tools.sh >/dev/null <<'EOF'
# Kubernetes toolchain shell setup (managed by kindctl.sh)

[ -f /etc/bash_completion ] && ! shopt -oq posix && . /etc/bash_completion

alias k=kubectl
alias kx=kubectx
alias kn=kubens
alias kgp='kubectl get pods -o wide'
alias kgn='kubectl get nodes -o wide'
alias kga='kubectl get all -A'

# Per-cluster shortcuts. Naming the context explicitly is safer than relying
# on whichever context happens to be current - the classic way to apply a dev
# manifest to prod is forgetting which context you were in.
alias kdev='kubectl --context kind-dev'
alias kstg='kubectl --context kind-stg'
alias kprod='kubectl --context kind-prod'

# Show the active context in the prompt so it is never a guess.
kube_ctx() {
  local c; c=$(kubectl config current-context 2>/dev/null) || return
  printf '(%s) ' "$c"
}
case "$PS1" in
  *kube_ctx*) ;;
  *) PS1='$(kube_ctx)'"$PS1" ;;
esac

# Make aliases inherit the full completion of the command they wrap.
if type __start_kubectl >/dev/null 2>&1; then
  complete -o default -F __start_kubectl k
  complete -o default -F __start_kubectl kdev
  complete -o default -F __start_kubectl kstg
  complete -o default -F __start_kubectl kprod
fi
EOF
  ok "  /etc/profile.d/kube-tools.sh"
}

cmd_tools() {
  detect_env

  install_kubectl    || true
  install_kind       || true
  install_helm       || true
  install_oc         || true
  install_kubectx    || true
  install_shell_extras

  echo
  log "installed"
  for b in kubectl oc helm kind kubectx kubens jq fzf; do
    if command -v "$b" >/dev/null; then
      printf '  %-9s %s\n' "$b" "$(command -v "$b")"
    else
      printf '  %-9s %sMISSING%s\n' "$b" "$C_RED" "$C_OFF"
    fi
  done
  echo
  warn "open a new shell, or run:  source /etc/profile.d/kube-tools.sh"
}

# --- inspection --------------------------------------------------------------

cmd_status() {
  log "tooling"
  kind version 2>/dev/null | head -1 || echo "  kind not installed"
  if [[ -n "$NODE_IMAGE" ]]; then
    echo "  node image: PINNED -> $NODE_IMAGE"
  else
    echo "  node image: kind default (tracks installed kind version)"
  fi
  echo

  log "clusters"
  kind get clusters 2>/dev/null || echo "  (none)"
  echo

  log "node containers"
  docker ps -a \
    --filter label=io.x-k8s.kind.cluster \
    --format 'table {{.Names}}\t{{.Status}}' || true
  echo

  for c in $(kind get clusters 2>/dev/null || true); do
    log "nodes in $c"
    kubectl --context "kind-${c}" get nodes -o wide 2>/dev/null \
      || warn "  api server unreachable (cluster stopped?)"
    echo
  done

  log "memory"
  free -m | head -2
  echo
  log "top consumers"
  docker stats --no-stream \
    --format 'table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}' 2>/dev/null \
    | head -12 || true
}

cmd_verify() {
  log "ingress endpoints"
  while read -r c; do
    local port="${HTTP_PORT[$c]:-}"
    [[ -n "$port" ]] || { warn "[$c] no port mapping known"; continue; }
    exists "$c" || { warn "[$c] cluster does not exist"; continue; }

    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://localhost:${port}" || echo "000")
    case "$code" in
      404)     ok   "[$c] :$port -> 404 (nginx up, no route yet)" ;;
      2*|3*)   ok   "[$c] :$port -> $code (route serving)" ;;
      000)     warn "[$c] :$port -> no response (controller down or wrong node)" ;;
      *)       warn "[$c] :$port -> $code" ;;
    esac
  done < <(targets "$@")
}

cmd_bootstrap() {
  [[ $EUID -eq 0 ]] || die "bootstrap needs root: sudo $0 bootstrap"
  cmd_docker
  echo
  tune
  echo
  cmd_tools
  echo
  cmd_up
}

# --- dispatch ----------------------------------------------------------------

usage() {
  # Print the leading comment block only, stopping at the first code line.
  awk 'NR>1 { if (/^#/) { sub(/^# ?/, ""); print } else { exit } }' "$0"
  exit 1
}

case "${1:-}" in
  bootstrap) shift; cmd_bootstrap ;;
  docker)  shift; cmd_docker ;;
  tune)    shift; tune ;;
  tools)   shift; cmd_tools ;;
  upgrade) shift; cmd_upgrade ;;
  create)  shift; cmd_create  "$@" ;;
  up)      shift; cmd_up      "$@" ;;
  ingress) shift; cmd_ingress "$@" ;;
  down)    shift; cmd_down    "$@" ;;
  start)   shift; cmd_start   "$@" ;;
  destroy) shift; cmd_destroy "$@" ;;
  status)  shift; cmd_status ;;
  verify)  shift; cmd_verify  "$@" ;;
  *)       usage ;;
esac
