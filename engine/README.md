# engine/

The SeyoAWE Community automation engine — a modular, workflow-driven platform that executes YAML-defined automation with built-in support for approvals, APIs, Git, Slack, email, and chatbot interactions.

## Contents

```
engine/
├── seyoawe.linux          # Pre-compiled engine binary (not in git — manual placement)
├── run.sh                 # Launcher script: ./run.sh linux | macos
├── configuration/
│   └── config.yaml        # Runtime configuration (ports, paths, module defaults)
├── modules/               # Built-in Python modules
│   ├── api_module/        # REST API calls
│   ├── chatbot_module/    # LLM-powered chatbot (OpenAI, Mistral)
│   ├── command_module/    # Shell command execution
│   ├── delegate_remote_workflow/  # Remote workflow delegation
│   ├── email_module/      # SMTP email + approval templates
│   ├── git_module/        # GitOps: branches, commits, PRs
│   ├── slack_module/      # Slack webhook messages
│   └── webform/           # React-based approval forms
├── workflows/
│   ├── community/         # Active workflows (loaded by engine)
│   │   └── hello-world.yaml
│   └── samples/           # Reference samples (ignored by engine via config)
├── lifetimes/             # Workflow state snapshots (runtime, PVC-backed in K8s)
└── logs/                  # Runtime logs (runtime, PVC-backed in K8s)
```

## Binary

The engine binary (`seyoawe.linux` / `seyoawe.macos.arm`) is not committed to git (19 MB). Obtain it from the upstream [seyoawe-community](https://github.com/yuribernstein/seyoawe-community) repository or instructor, place it in this directory, and `chmod +x`.

## Configuration

`configuration/config.yaml` controls:

| Key | Purpose |
|-----|---------|
| `app.port` | Flask HTTP port (default: 8080) |
| `app.customer_id` | API route prefix — workflows register at `POST /api/<customer_id>/<name>` |
| `module_dispatcher.port` | Module dispatcher port (default: 8081) |
| `directories.*` | Runtime directories for modules, workflows, lifetimes, logs |
| `module_defaults.*` | Default settings per module (API keys, SMTP, Slack webhooks) |

In Kubernetes, this file is replaced by a ConfigMap mount (see `k8s/engine/configmap.yaml`).

## API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/community/<workflow_name>` | POST | Trigger a workflow by name (returns `{"status":"accepted"}`) |
| `/` | GET | Returns 404 (no root handler — used as health probe since any HTTP response confirms Flask is up) |

There is no `GET /health` endpoint. Health probes use TCP socket checks or plain HTTP requests.

## Running Locally

```bash
cd engine
chmod +x run.sh seyoawe.linux
./run.sh linux    # Flask starts on :8080 and :8081

# Test
curl -X POST http://localhost:8080/api/community/hello-world \
  -H "Content-Type: application/json" -d '{}'
```

## Module Loader

The engine resolves modules from `modules/modules/<name>/`. A self-referencing symlink `modules/modules → modules/` satisfies this. In Docker, this is created automatically by `RUN cd modules && ln -sf . modules` in the Dockerfile.

## In Docker / Kubernetes

See `docker/engine/Dockerfile` for containerization and `k8s/engine/` for the StatefulSet deployment. Logs and lifetimes persist on a 2Gi PVC mounted at `/app/data`.
