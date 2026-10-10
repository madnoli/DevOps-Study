# nginx load-balanced across 5 pods, showing each pod's IP

You open `http://podip.localhost:8080` in a browser. Each time you refresh, the
page shows the **IP address, name and node of the pod** that answered. With 5
pods behind the load balancer, the IP changes as requests are spread across
them.

```
browser ──► localhost:8080 ──► ingress-nginx ──► Service "podip" ──► pod 1  10.10.1.4
             (kind host port)   (L7 load balancer)  (ClusterIP)     ├─► pod 2  10.10.2.7
                                                                    ├─► pod 3  10.10.1.5
                                                                    ├─► pod 4  10.10.2.8
                                                                    └─► pod 5  10.10.1.6
```

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Builds the image `podip-nginx:1.0` from `nginx:1.27-alpine` |
| `default.conf.template` | nginx config: `/` shows an HTML page, `/ip` returns plain text, `/healthz` is for probes |
| `k8s/podip.yaml` | Deployment (5 replicas), Service and Ingress |

## How it works

1. **How a pod learns its own IP.** Kubernetes passes the pod's details to the container as environment variables through the *downward API*:
   ```yaml
   env:
     - name: POD_IP
       valueFrom: { fieldRef: { fieldPath: status.podIP } }
   ```
   `POD_NAME` (`metadata.name`) and `NODE_NAME` (`spec.nodeName`) are passed the same way.
2. **How the IP gets into the page.** When the official nginx image starts, it renders `/etc/nginx/templates/*.template` and replaces each `${VAR}` with the value of that environment variable. So the page shows that pod's real IP, and you don't need an extra script or a custom entrypoint.
3. **Why a refresh shows a different pod.** The response sets `Cache-Control: no-store`, so the browser asks again on every refresh. ingress-nginx sends each request to the next pod (round robin).
4. **Which object does which job:**
   - **The Deployment** keeps 5 replicas running and spreads them across nodes with `topologySpreadConstraints`.
   - **The Service** gives the pods one stable address.
   - **The Ingress** is the load balancer you reach from your browser.

> **Why not `Service type: LoadBalancer`?** On a cloud such as EKS or AKS, that type
> gets you a cloud load balancer. kind has no cloud provider, so the service would
> sit in `<pending>`. On kind, use an Ingress, or install MetalLB or
> cloud-provider-kind if you specifically want to practise the LoadBalancer type.

## Steps

All commands run from the repo root on the machine where your kind clusters run.

### 1. Make sure the cluster and ingress are up

```bash
bash kindctl.sh up dev        # creates the dev cluster with ingress-nginx (safe to re-run)
kubectl --context kind-dev get nodes
```

### 2. Build the Docker image

```bash
docker build -t podip-nginx:1.0 nginx-podip/
```

Optional: test the image on its own, outside Kubernetes:

```bash
docker run --rm -d --name podip-test -p 18080:80 podip-nginx:1.0
curl localhost:18080/ip        # -> "unknown local docker" (the fallback values from the Dockerfile)
docker rm -f podip-test
```

### 3. Load the image into the kind cluster

kind nodes are containers with their own image store, so they can't see images on
your host. Load the image into them:

```bash
kind load docker-image podip-nginx:1.0 --name dev
```

You don't need a registry for this. The Deployment uses `imagePullPolicy: IfNotPresent`, so it uses the image you loaded.

> If you rebuild the image, give it a new tag (for example `1.1`), load it again,
> and update the tag in `k8s/podip.yaml`. Reusing a tag can leave old copies on
> some nodes.

### 4. Deploy

```bash
kubectl --context kind-dev apply -f nginx-podip/k8s/podip.yaml
kubectl --context kind-dev rollout status deploy/podip
kubectl --context kind-dev get pods -l app=podip -o wide     # 5 pods, their IPs and nodes
```

### 5. Open it in the browser

Go to **http://podip.localhost:8080** and refresh a few times. The IP should change.

- Use port `8080` for `dev`, `8081` for `stg` and `8082` for `prod`.
- `*.localhost` resolves to 127.0.0.1 automatically, so you don't need to edit `/etc/hosts`.
- If you're browsing from a different machine from the kind host, use `http://<host-ip>:8080` with the header `Host: podip.localhost`, or add `<host-ip> podip.localhost` to that machine's hosts file.

### 6. Prove the traffic is spread across all 5 pods

```bash
for i in $(seq 1 20); do curl -s http://podip.localhost:8080/ip; done | sort | uniq -c
```

If your curl doesn't resolve `*.localhost`, send the host header yourself:

```bash
for i in $(seq 1 20); do curl -s -H 'Host: podip.localhost' http://localhost:8080/ip; done | sort | uniq -c
```

Expected output: 5 different pod IPs, about 4 hits each.

### 7. Experiment

```bash
# Scale and watch the new IPs join the rotation
kubectl --context kind-dev scale deploy/podip --replicas=8

# Kill a pod: the Deployment replaces it with a new IP, and traffic never stops
kubectl --context kind-dev delete $(kubectl --context kind-dev get pod -l app=podip -o name | head -1)

# See the endpoints the Service is balancing over
kubectl --context kind-dev get endpointslices -l kubernetes.io/service-name=podip
```

### 8. Clean up

```bash
kubectl --context kind-dev delete -f nginx-podip/k8s/podip.yaml
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Pods are stuck in `ErrImagePull` / `ImagePullBackOff` | You skipped step 3. Run `kind load docker-image podip-nginx:1.0 --name dev`. |
| You get `404 Not Found` from nginx | The request didn't match the host rule. Use `podip.localhost`, not plain `localhost`. |
| The browser always shows the same IP | Do a hard refresh (Ctrl+Shift+R), or use the curl loop. Some browsers also reuse a single connection, but ingress-nginx still balances each request. |
| No response on port 8080 | The ingress controller isn't running. Run `bash kindctl.sh ingress dev` and then `bash kindctl.sh verify dev`. |
