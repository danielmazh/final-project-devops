# k8s/

Kubernetes manifests for deploying the SeyoAWE engine to EKS as a StatefulSet with persistent storage, health probes, and configuration injection.

## Files

```
k8s/
├── namespace.yaml              # Creates namespaces: seyoawe + monitoring
└── engine/
    ├── statefulset.yaml        # StatefulSet: 1 replica, probes, PVC, resource limits
    ├── service.yaml            # ClusterIP service: ports 8080 + 8081
    └── configmap.yaml          # Engine config.yaml adapted for K8s
```

## Architecture Inside the Cluster

```
Service: seyoawe-engine (ClusterIP)
  │  ports: 8080 (http), 8081 (dispatcher)
  ▼
StatefulSet: seyoawe-engine (replicas: 1)
  └── Pod: seyoawe-engine-0
        │
        ├── Container: engine
        │   Image: danielmazh/seyoawe-engine:0.1.1
        │   Ports: 8080, 8081
        │   Liveness:  tcpSocket :8080 (delay 30s, period 15s)
        │   Readiness: tcpSocket :8080 (delay 15s, period 10s)
        │   Resources: 100m–500m CPU, 256Mi–512Mi memory
        │
        ├── Volume: config-vol (ConfigMap → /app/configuration/config.yaml)
        │   subPath mount — replaces only the config file, not the directory
        │
        └── Volume: data (PVC 2Gi gp2 → /app/data/)
            ├── logs/       (engine runtime logs)
            └── lifetimes/  (workflow state snapshots)
```

## Deployment

```bash
# Apply all manifests
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/engine/

# Verify
kubectl get pods -n seyoawe             # seyoawe-engine-0  1/1  Running
kubectl get pvc -n seyoawe              # data-seyoawe-engine-0  Bound  2Gi
kubectl get svc -n seyoawe              # seyoawe-engine  ClusterIP  :8080/:8081

# Test the API
kubectl port-forward svc/seyoawe-engine 8090:8080 -n seyoawe
curl -X POST http://localhost:8090/api/community/hello-world \
  -H "Content-Type: application/json" -d '{}'
# {"status":"accepted"}

# View logs
kubectl logs seyoawe-engine-0 -n seyoawe --tail=50

# Restart (e.g., after image update)
kubectl rollout restart statefulset/seyoawe-engine -n seyoawe
kubectl rollout status statefulset/seyoawe-engine -n seyoawe
```

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| **StatefulSet** (not Deployment) | Required by rubric; provides stable pod identity and per-pod PVC |
| **tcpSocket** probe (not httpGet) | Engine has no `GET /health` endpoint; TCP check confirms Flask is accepting connections |
| **subPath** ConfigMap mount | Avoids overwriting the entire `/app/configuration/` directory |
| **Single PVC** at `/app/data` | Simpler than two separate volumeClaimTemplates; config points `logs` and `lifetimes` inside it |
| **ClusterIP** service (not LoadBalancer) | No AWS ELB cost; access via `kubectl port-forward` for PoC |
| **1 replica** | Conserves t3.medium node capacity while still demonstrating StatefulSet mechanics |

## ConfigMap

`configmap.yaml` contains the engine `config.yaml` with Kubernetes-specific adaptations:

- `base_url: http://seyoawe-engine:8080` (K8s service DNS name)
- `directories.lifetimes: ./data/lifetimes` (inside PVC mount)
- `directories.logs: ./data/logs` (inside PVC mount)
- `app.customer_id: community` (API route prefix)
- Logging level: `INFO` (reduced from local DEBUG)
