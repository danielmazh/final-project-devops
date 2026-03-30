# 0005 — Phase 3: Containerization (Docker)

## 1. Background & Problem

The application has two components that need to be containerized independently:

- **Engine** — pre-compiled binary (`seyoawe.linux`) + Python modules + config. The binary is **not in git** and must be present in the build context before building the image.
- **CLI (`sawectl`)** — pure Python, no binary dependency. Fully self-contained.

Neither component has a Dockerfile yet. The rubric requires: Dockerfiles for both, CLI unit tests (pytest, minimum 5 cases), images tagged with the `VERSION` file via `--build-arg`.

**Root cause:** No Docker packaging layer; no automated test suite for the CLI.

## 2. Questions & Answers

| Question | Answer |
|----------|--------|
| Engine binary for Docker? | Must be present at `engine/seyoawe.linux` before `docker build`. The Dockerfile validates this with an explicit `RUN test -f` guard and fails with a clear message if missing. |
| How does Jenkins CI get the binary? | Phase 4 Jenkinsfile will add a pre-build step. For now the binary is a documented manual prerequisite. |
| Version injection strategy? | Both Dockerfiles accept `ARG VERSION=dev`. Engine uses it as an OCI label. CLI additionally patches `VERSION = "..."` in `sawectl.py` via `sed` at build time so `--help` shows the correct version. |
| Base image? | `python:3.11-slim` for both — slim keeps image size small; Python 3.11 covers all module deps. |
| Module Python deps? | `requests`, `pyyaml`, `jinja2`, `gitpython` — extracted from module imports. Engine Dockerfile installs these. |
| CLI test framework? | `pytest` (already in `requirements-infra.txt`). Tests live in `cli/tests/`. |

## 3. Design & Solution

### 3.1 Engine Dockerfile (`docker/engine/Dockerfile`)

```
Base:       python:3.11-slim
Build ARG:  VERSION (tagged as OCI label)
COPY:       engine/ → /app  (binary + config + modules + workflows)
Guard:      RUN test -f seyoawe.linux  (fails with message if binary absent)
Deps:       requests pyyaml jinja2 gitpython
Ports:      EXPOSE 8080 8081
Healthcheck: curl /health (30s interval, 30s start period)
Entrypoint: ./seyoawe.linux
```

### 3.2 CLI Dockerfile (`docker/cli/Dockerfile`)

```
Base:       python:3.11-slim
Build ARG:  VERSION (label + sed-patched into sawectl.py)
COPY:       cli/ → /app
Deps:       pip install -r requirements.txt
Entrypoint: python sawectl.py
```

### 3.3 CLI unit tests (`cli/tests/test_sawectl.py`)

Seven test cases across three classes:

| Class | Tests |
|-------|-------|
| `TestLoadYaml` | valid YAML returns dict; invalid YAML exits; empty YAML exits |
| `TestSchemaValidation` | `dsl.schema.json` is valid JSON schema; valid sample workflow validates |
| `TestCLI` | `--help` exits 0; `VERSION` constant is semver string; `validate-workflow` on sample passes |

### 3.4 Build commands

```bash
# CLI (no binary needed)
docker build -f docker/cli/Dockerfile \
  -t seyoawe-cli:0.1.0 --build-arg VERSION=0.1.0 .

# Engine (requires engine/seyoawe.linux)
docker build -f docker/engine/Dockerfile \
  -t seyoawe-engine:0.1.0 --build-arg VERSION=0.1.0 .
```

## 4. Implementation Plan

1. Create `0005_phase3_containerization.md` (this file).
2. Create `docker/engine/Dockerfile` and `docker/cli/Dockerfile`.
3. Create `.dockerignore` at project root.
4. Create `cli/tests/__init__.py`, `cli/tests/conftest.py`, `cli/tests/test_sawectl.py`.
5. Run `pytest cli/tests/ -v` — all tests must pass.
6. Build CLI Docker image, test `docker run seyoawe-cli:0.1.0 --help`.
7. Build Engine Docker image if binary is available; otherwise document and skip.

## 5. Examples

- ✅ `docker build -f docker/cli/Dockerfile --build-arg VERSION=0.2.0 .` → image with `VERSION = "0.2.0"` in sawectl.py.
- ❌ `docker build -f docker/engine/Dockerfile .` without binary → `seyoawe.linux not found` error at build time.
- ✅ `pytest cli/tests/ -v` → 7 passed in < 3 seconds.

## 6. Trade-offs

| Choice | Rationale |
|--------|-----------|
| Binary guard in Dockerfile vs. silent COPY | Fail fast with a clear message is better than a broken image. |
| `sed` version injection in CLI Dockerfile | Zero code changes to sawectl.py; works at build time. |
| `python:3.11-slim` over `alpine` | Alpine requires musl libc fixes for compiled wheels (gitpython); slim avoids this entirely. |

## 7. Verification Criteria

- [ ] `pytest cli/tests/ -v` → 7 passed, 0 failed.
- [ ] `docker build -f docker/cli/Dockerfile --build-arg VERSION=0.1.0 .` → exits 0.
- [ ] `docker run seyoawe-cli:0.1.0 --help` → prints usage.
- [ ] `docker build -f docker/engine/Dockerfile --build-arg VERSION=0.1.0 .` → exits 0 (requires binary).
- [ ] `docker run seyoawe-engine:0.1.0` → responds on 8080 (requires binary).

---

## Implementation Results

**When:** 2026-03-30

### Test results

- `pytest cli/tests/ -v` → **13 passed in 1.36s** (0 failed, 0 skipped)
- Fix applied: `conftest.py` path constants moved inline to `test_sawectl.py` (pytest does not expose conftest as an importable module)

### Docker build results

- `seyoawe-cli:0.1.0` builds and runs ✅ — `--help` prints full usage, `VERSION = "0.1.0"` injected via `sed`
- `seyoawe-engine:0.1.0` builds and runs ✅ — binary copied from `seyoawe-community/seyoawe.linux`; added `git` to apt deps (engine bundles gitpython); health probe confirmed `healthy`
- Health probe: `/health` route does not exist; Dockerfile HEALTHCHECK uses `curl -s http://localhost:8080/` (returns 0 on any HTTP response — confirms Flask is accepting requests)

### Deviations

- 13 tests written (exceeded minimum 5 from plan) — extra coverage for module manifest and version file
- conftest.py retained for pytest plugin hook context but constants moved to test file for direct import compatibility
