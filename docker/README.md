# docker/

Dockerfiles for both application components. Build context is always the **repository root** (not this directory).

## Files

```
docker/
├── engine/
│   └── Dockerfile     # 50 lines — engine binary + modules + config
└── cli/
    └── Dockerfile     # 20 lines — Python CLI tool
```

## Engine Image

```bash
# Build (from repo root — engine/seyoawe.linux must be present)
docker build -f docker/engine/Dockerfile -t seyoawe-engine:0.1.1 --build-arg VERSION=0.1.1 .

# Run
docker run -d -p 8080:8080 -p 8081:8081 seyoawe-engine:0.1.1

# Test
curl -X POST http://localhost:8080/api/community/hello-world \
  -H "Content-Type: application/json" -d '{}'
```

**Build flow:**

```
python:3.11-slim
  │
  ├── apt install curl git          (healthcheck + gitpython dependency)
  ├── pip install requests pyyaml   (module Python dependencies)
  │   jinja2 gitpython
  ├── COPY engine/ → /app           (binary + config + modules + workflows)
  ├── ln -sf . modules/modules      (module loader symlink)
  ├── test -f seyoawe.linux         (fail-fast if binary missing)
  ├── chmod +x seyoawe.linux
  ├── EXPOSE 8080 8081
  ├── HEALTHCHECK curl :8080/       (any HTTP response = healthy)
  └── ENTRYPOINT ./seyoawe.linux
```

The binary guard at build time produces a clear error message if `engine/seyoawe.linux` is absent, preventing silent creation of a broken image.

## CLI Image

```bash
# Build
docker build -f docker/cli/Dockerfile -t seyoawe-cli:0.1.1 --build-arg VERSION=0.1.1 .

# Run
docker run --rm seyoawe-cli:0.1.1 --help
docker run --rm seyoawe-cli:0.1.1 validate-workflow --workflow /path/to/wf.yaml
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
| `danielmazh/seyoawe-engine` | DockerHub | `0.1.1`, `latest` |
| `danielmazh/seyoawe-cli` | DockerHub | `0.1.1`, `latest` |
