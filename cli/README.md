# cli/

The `sawectl` CLI tool — validates, scaffolds, and triggers SeyoAWE workflows against a running engine instance.

## Contents

```
cli/
├── sawectl.py             # Main CLI entry point (630 lines)
├── requirements.txt       # Python dependencies: pyyaml, jsonschema, requests, argparse
├── dsl.schema.json        # Workflow YAML schema (Draft 2020-12)
├── module.schema.json     # Module manifest schema
└── tests/
    ├── __init__.py
    ├── conftest.py         # Pytest path setup
    └── test_sawectl.py     # 13 unit tests across 5 classes
```

## Commands

```bash
# Show help
python sawectl.py --help

# Validate a workflow against schema + module manifests
python sawectl.py validate-workflow \
  --workflow ../engine/workflows/samples/scheduled_api_watchdog.yaml \
  --modules ../engine/modules

# Scaffold a new workflow
python sawectl.py init workflow hello --minimal

# Scaffold a new module
python sawectl.py init module mymodule

# Trigger a workflow on a running engine
python sawectl.py run --workflow path/to/workflow.yaml --server localhost:8080
```

## Unit Tests

13 tests across 5 classes, all passing in < 2 seconds:

| Class | Tests | What it verifies |
|-------|-------|-----------------|
| `TestLoadYaml` | 3 | YAML loading: valid dict return, invalid YAML exits, empty YAML exits |
| `TestSchemaValidation` | 3 | Schema files are valid JSON, sample workflow loads correctly |
| `TestVersion` | 3 | `VERSION` constant exists, is semver `X.Y.Z`, root `VERSION` file exists |
| `TestCLISubprocess` | 2 | `--help` exits 0, `validate-workflow` on sample returns PASSED |
| `TestModuleManifest` | 2 | Module manifest loading works, missing module returns None |

```bash
# Run tests (from repo root, with venv active)
pytest cli/tests/ -v
```

## Version Injection

The `VERSION` constant at line 3 of `sawectl.py` is patched at Docker build time via `sed` in `docker/cli/Dockerfile`:

```dockerfile
RUN sed -i "s/^VERSION = \"[^\"]*\"/VERSION = \"${VERSION}\"/" sawectl.py
```

## In Docker

```bash
docker build -f docker/cli/Dockerfile -t seyoawe-cli:0.1.2 --build-arg VERSION=0.1.2 .
docker run --rm seyoawe-cli:0.1.2 --help
```

## Linting

`flake8` with project-level `.flake8` config (tolerates upstream code style conventions):

```bash
flake8 cli/
```
