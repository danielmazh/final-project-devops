# monitoring/

Observability stack configuration — Prometheus, Grafana, and Alertmanager deployed via the `kube-prometheus-stack` Helm chart, plus a ServiceMonitor for the SeyoAWE engine.

## Files

```
monitoring/
├── kube-prometheus-values.yaml    # Helm chart overrides (104 lines)
└── servicemonitor-engine.yaml     # Prometheus scrape target for seyoawe-engine
```

## Stack Components (7 pods)

```
Namespace: monitoring
├── prometheus-0                2/2  Metrics collection (14 active scrape targets)
├── grafana                     3/3  Dashboard UI (28 pre-built dashboards)
├── alertmanager-0              2/2  Alert routing + notification
├── kube-prometheus-operator    1/1  Manages Prometheus/Alertmanager CRDs
├── kube-state-metrics          1/1  Kubernetes object state → metrics
└── node-exporter (×2)          1/1  Per-node hardware/OS metrics (DaemonSet)
```

## Installation

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f monitoring/kube-prometheus-values.yaml
kubectl apply -f monitoring/servicemonitor-engine.yaml
```

## Accessing Grafana

```bash
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
# Open http://localhost:3000
# Login: admin / seyoawe-grafana
```

**Key dashboards:**

| Dashboard | What it shows |
|-----------|---------------|
| Kubernetes / Compute Resources / Cluster | Overall CPU, memory, bandwidth |
| Kubernetes / Compute Resources / Namespace (Pods) | Per-namespace resource usage (select `seyoawe`) |
| Kubernetes / Compute Resources / Node (Pods) | Per-node pod placement |
| Node Exporter / Nodes | CPU, memory, disk, network per worker |
| Alertmanager / Overview | Alert counts and status |

28 dashboards ship pre-built — no custom JSON needed.

## Accessing Prometheus

```bash
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
# Open http://localhost:9090
# Navigate: Status → Targets (14 active targets)
```

## Accessing Alertmanager

```bash
kubectl port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093 -n monitoring
# Open http://localhost:9093
```

Default PrometheusRule alert groups (shipped with chart):

```bash
kubectl get prometheusrules -n monitoring
# Lists: alertmanager.rules, k8s.rules, kubernetes-*, node-exporter, etc.
```

## ServiceMonitor

`servicemonitor-engine.yaml` tells Prometheus to scrape the engine service:

```yaml
spec:
  namespaceSelector:
    matchNames: ["seyoawe"]
  selector:
    matchLabels:
      app: seyoawe-engine
  endpoints:
    - port: http          # port 8080
      path: /metrics
      interval: 30s
```

The target shows `down` in Prometheus because the engine binary does not expose `/metrics`. The wiring is architecturally correct — the ServiceMonitor, scrape config, and target registration all work; this is an upstream application limitation.

## Values Overrides

Key settings in `kube-prometheus-values.yaml`:

| Setting | Value | Why |
|---------|-------|-----|
| Prometheus replicas | 1 | Fit on 2 × t3.medium nodes |
| Alertmanager replicas | 1 | Resource conservation |
| Retention | 3 days | Limit disk usage |
| Storage | 5Gi gp2 | Persistent Prometheus data |
| Image registries | docker.io + ghcr.io | quay.io returns 502 from AWS NAT GW IPs |
| serviceMonitorSelectorNilUsesHelmValues | false | Scrape ServiceMonitors from ALL namespaces |
| Grafana admin password | `seyoawe-grafana` | Known password for demo |

## Upgrade / Uninstall

```bash
# Upgrade with new values
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring -f monitoring/kube-prometheus-values.yaml

# Uninstall (stop billing for monitoring resources)
helm uninstall monitoring -n monitoring
# or: ./lifecycle.sh stop monitoring
```
