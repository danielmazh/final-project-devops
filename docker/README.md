# docker/

Dockerfiles for both application components. Build context is always the **repository root** (not this directory).

## Files

```
docker/
├── engine/
│   ├── Dockerfile     # Engine binary + metrics exporter + modules + config
│   └── entrypoint.sh  # Starts metrics exporter, then execs the engine binary
└── cli/
    └── Dockerfile     # Python CLI tool
```

## Engine Image

```bash
# Build (from repo root — engine/seyoawe.linux must be present)
docker build -f docker/engine/Dockerfile -t seyoawe-engine:0.1.2 --build-arg VERSION=0.1.2 .

# Run
docker run -d -p 8080:8080 -p 8081:8081 -p 9113:9113 seyoawe-engine:0.1.2

# Test
curl -X POST http://localhost:8080/api/community/hello-world \
  -H "Content-Type: application/json" -d '{}'
```

**Build flow:**

```
python:3.11-slim
  │
  ├── apt install curl git             (healthcheck + gitpython dependency)
  ├── pip install requests pyyaml      (module Python dependencies)
  │   jinja2 gitpython prometheus_client
  ├── COPY engine/ → /app              (binary + config + modules + workflows + metrics_exporter.py)
  ├── ln -sf . modules/modules         (module loader symlink)
  ├── test -f seyoawe.linux            (fail-fast if binary missing)
  ├── chmod +x seyoawe.linux
  ├── EXPOSE 8080 8081 9113
  ├── HEALTHCHECK curl :8080/          (any HTTP response = healthy)
  ├── COPY entrypoint.sh → /app/
  └── ENTRYPOINT /app/entrypoint.sh    (starts metrics exporter, then execs engine)
```

The binary guard at build time produces a clear error message if `engine/seyoawe.linux` is absent, preventing silent creation of a broken image.

## CLI Image

```bash
# Build
docker build -f docker/cli/Dockerfile -t seyoawe-cli:0.1.2 --build-arg VERSION=0.1.2 .

# Run
docker run --rm seyoawe-cli:0.1.2 --help
docker run --rm seyoawe-cli:0.1.2 validate-workflow --workflow /path/to/wf.yaml
```

**Build flow:**

```
python:3.11-slim
  │
  ├── COPY requirements.txt → pip install
  ├── COPY cli/ → /app
  ├── sed → inject VERSION into sawectl.py
  └── ENTRYPOINT python sawectl.py
```

## Version Injection

Both Dockerfiles accept `--build-arg VERSION=X.Y.Z`:
- **Engine:** Sets OCI label `org.opencontainers.image.version`
- **CLI:** OCI label + `sed` patches `VERSION = "..."` constant in `sawectl.py`

## Published Images

| Image | Registry | Tags |
|-------|----------|------|
| `danielmazh/seyoawe-engine` | DockerHub | `0.1.2`, `latest` |
| `danielmazh/seyoawe-cli` | DockerHub | `0.1.2`, `latest` |
