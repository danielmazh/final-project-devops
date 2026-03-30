# 0007 — Phase 5: CD Pipeline & Kubernetes Deployment

## 1. Background & Problem

The SeyoAWE engine Docker image is published to DockerHub but is not running anywhere. The Kubernetes namespaces `seyoawe` and `monitoring` exist on the EKS cluster but are empty. The CD pipeline (`Jenkinsfile.cd`) is written but the K8s manifests it applies do not exist yet.

**Root cause:** No Kubernetes manifests defined; CD pipeline has no resources to apply.

## 2. Questions & Answers

| Question | Answer |
|----------|--------|
| StatefulSet or Deployment? | **StatefulSet** — required by rubric; gives stable pod identity (`seyoawe-engine-0`) and volumeClaimTemplates for per-pod PVCs (logs, lifetimes). |
| How many replicas? | **1** for PoC — satisfies the rubric without consuming excessive node capacity. |
| Config injection? | `configuration/config.yaml` mounted as a **ConfigMap** at `/app/configuration/config.yaml`. Decouples config from the image. |
| Persistent storage for what? | Two dirs: `/app/logs` and `/app/lifetimes`. One `volumeClaimTemplate` per pod mounts both at `/app/data`; the engine config will point there. Simpler than two separate PVCs in a PoC. Actually: two separate PVCs via one volumeClaimTemplate covering `/app/data` and symlinking both dirs is overly complex — use a **single PVC** mounting at `/app/data`, set config paths to `./data/logs` and `./data/lifetimes`. |
| Health probe endpoint? | No `GET /health` exists in this binary. Use **tcpSocket** probe on port 8080. |
| Service type? | **ClusterIP** — no external load balancer needed for PoC; `kubectl port-forward` for demo. |
| K8s config.yaml `base_url`? | Must point to the ClusterIP service name: `http://seyoawe-engine:8080`. |
| `modules/modules` symlink in K8s? | Already baked into the Docker image via `RUN cd modules && ln -sf . modules`. No extra manifest needed. |

## 3. Design & Solution

### 3.1 Manifest layout

```
k8s/
├── namespace.yaml          # seyoawe + monitoring namespaces
└── engine/
    ├── configmap.yaml      # engine configuration/config.yaml as ConfigMap
    ├── statefulset.yaml    # StatefulSet: 1 replica, probes, PVC, ConfigMap mount
    └── service.yaml        # ClusterIP: ports 8080 + 8081
```

No separate `pvc.yaml` — volumeClaimTemplates inside the StatefulSet generate PVCs automatically.

### 3.2 ConfigMap (`k8s/engine/configmap.yaml`)

Engine `config.yaml` as a ConfigMap key. Mounted at `/app/configuration/config.yaml`.  
Key changes from local version:
- `base_url: http://seyoawe-engine:8080` (K8s service name)
- `directories.logs: ./data/logs`
- `directories.lifetimes: ./data/lifetimes`
- `directories.workdir: .`
- `directories.modules: ./modules`
- `directories.workflows: ./workflows`

### 3.3 StatefulSet (`k8s/engine/statefulset.yaml`)

```
name:     seyoawe-engine
ns:       seyoawe
replicas: 1
image:    danielmazh/seyoawe-engine:0.1.1
ports:    8080 (app), 8081 (dispatcher)
probes:
  liveness:  tcpSocket :8080  (initial: 30s, period: 15s)
  readiness: tcpSocket :8080  (initial: 15s, period: 10s)
volumes:
  - name: config-vol  (ConfigMap → /app/configuration/config.yaml)
  - name: data        (volumeClaimTemplate 2Gi gp3 → /app/data)
resources:
  requests: cpu 100m, memory 256Mi
  limits:   cpu 500m, memory 512Mi
```

### 3.4 Service (`k8s/engine/service.yaml`)

```
type: ClusterIP
ports: 8080 (app), 8081 (dispatcher)
selector: app=seyoawe-engine
```

### 3.5 CD Pipeline flow (complete)

```
Jenkins (EC2) → Terraform init/plan → Approval gate → Terraform apply
             → Ansible configure-eks (kubeconfig refresh)
             → kubectl apply -f k8s/namespace.yaml
             → kubectl apply -f k8s/engine/
             → kubectl set image statefulset/seyoawe-engine engine=danielmazh/seyoawe-engine:$VERSION
             → kubectl rollout status statefulset/seyoawe-engine -n seyoawe --timeout=300s
             → git tag deploy-v$VERSION
```

## 4. Implementation Plan

1. Create design log `0007` (this file).
2. Write `k8s/namespace.yaml`, `k8s/engine/configmap.yaml`, `k8s/engine/statefulset.yaml`, `k8s/engine/service.yaml`.
3. Apply locally: `kubectl apply -f k8s/` — verify pods reach Running state.
4. Verify health probes pass: `kubectl describe pod seyoawe-engine-0 -n seyoawe`.
5. Verify PVC bound: `kubectl get pvc -n seyoawe`.
6. Update `Jenkinsfile.cd` with correct image reference and namespace.
7. Trigger CD pipeline via Jenkins (skipping Terraform/Ansible since infra is already up).
8. Commit, push, merge.

## 5. Examples

- ✅ `kubectl get pods -n seyoawe` → `seyoawe-engine-0  1/1  Running`
- ✅ `kubectl get pvc -n seyoawe` → `data-seyoawe-engine-0  Bound`
- ❌ `httpGet /health` probe → engine has no health route; use `tcpSocket` instead.
- ✅ `kubectl port-forward svc/seyoawe-engine 8080:8080 -n seyoawe` → `POST /api/community/hello-world` returns `{"status":"accepted"}`

## 6. Trade-offs

| Choice | Rationale |
|--------|-----------|
| Single PVC at `/app/data`, config paths pointing inside | Simpler than two volumeClaimTemplates; satisfies persistent storage rubric requirement. |
| `tcpSocket` probe instead of `httpGet` | Engine has no `/health` route; TCP probe is accurate and avoids false failures. |
| ClusterIP (not LoadBalancer) | No AWS ELB cost; port-forward sufficient for demonstration. |
| 1 replica | Conserves t3.medium node capacity; StatefulSet kind still satisfies rubric. |

## 7. Verification Criteria

- [ ] `kubectl get pods -n seyoawe` → `seyoawe-engine-0  1/1  Running`
- [ ] `kubectl get pvc -n seyoawe` → `data-seyoawe-engine-0  Bound`
- [ ] `kubectl describe pod seyoawe-engine-0 -n seyoawe` → liveness/readiness probes passing
- [ ] Engine API reachable: `kubectl port-forward svc/seyoawe-engine 8090:8080 -n seyoawe` + `curl -X POST localhost:8090/api/community/hello-world -H "Content-Type: application/json" -d '{}'` → `{"status":"accepted"}`
- [ ] CD pipeline runs end-to-end (kubectl stages green, rollout status 1/1)

---

## Implementation Results

_(Append only after apply and pipeline execution.)_
