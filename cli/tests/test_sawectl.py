"""
CLI unit tests for sawectl.py

Coverage:
  - YAML loading (valid, invalid, empty)
  - JSON schema loading
  - Schema validation (valid workflow passes)
  - VERSION constant is semver format
  - --help exits 0 and prints usage
  - validate-workflow command succeeds on a real sample
  - load_module_manifest returns correct structure
"""

import json
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

# Path constants — resolved relative to this file
_TESTS_DIR   = Path(__file__).parent
CLI_DIR      = _TESTS_DIR.parent
REPO_ROOT    = CLI_DIR.parent
SCHEMAS_DIR  = CLI_DIR
SAMPLES_DIR  = REPO_ROOT / "engine" / "workflows" / "samples"
MODULES_DIR  = REPO_ROOT / "engine" / "modules"
VERSION_FILE = REPO_ROOT / "VERSION"

import sawectl


# ── YAML loading ─────────────────────────────────────────────────────────────

class TestLoadYaml:
    def test_valid_yaml_returns_dict(self, tmp_path):
        f = tmp_path / "valid.yaml"
        f.write_text("name: hello\nsteps: []\n")
        result = sawectl.load_yaml(str(f))
        assert result == {"name": "hello", "steps": []}

    def test_invalid_yaml_exits(self, tmp_path):
        f = tmp_path / "bad.yaml"
        f.write_text(": {{{{ not valid yaml\n")
        with pytest.raises(SystemExit):
            sawectl.load_yaml(str(f))

    def test_empty_yaml_exits(self, tmp_path):
        f = tmp_path / "empty.yaml"
        f.write_text("")
        with pytest.raises(SystemExit):
            sawectl.load_yaml(str(f))


# ── Schema validation ─────────────────────────────────────────────────────────

class TestSchemaValidation:
    def test_dsl_schema_file_exists_and_is_valid_json(self):
        schema_path = SCHEMAS_DIR / "dsl.schema.json"
        assert schema_path.exists(), "dsl.schema.json not found in cli/"
        with open(schema_path) as f:
            schema = json.load(f)
        assert "properties" in schema or "$defs" in schema

    def test_module_schema_file_exists_and_is_valid_json(self):
        schema_path = SCHEMAS_DIR / "module.schema.json"
        assert schema_path.exists(), "module.schema.json not found in cli/"
        with open(schema_path) as f:
            schema = json.load(f)
        assert isinstance(schema, dict)

    def test_sample_workflow_loads_without_error(self):
        samples = list(SAMPLES_DIR.glob("*.yaml"))
        assert samples, "No sample workflows found under engine/workflows/samples/"
        data = sawectl.load_yaml(str(samples[0]))
        assert data is not None


# ── VERSION constant ──────────────────────────────────────────────────────────

class TestVersion:
    def test_version_constant_exists(self):
        assert hasattr(sawectl, "VERSION")

    def test_version_constant_is_semver(self):
        parts = sawectl.VERSION.split(".")
        assert len(parts) == 3, f"Expected semver X.Y.Z, got: {sawectl.VERSION}"
        assert all(p.isdigit() for p in parts), \
            f"VERSION parts must be numeric, got: {sawectl.VERSION}"

    def test_version_file_exists(self):
        assert VERSION_FILE.exists(), "Root VERSION file not found"
        content = VERSION_FILE.read_text().strip()
        parts = content.split(".")
        assert len(parts) == 3


# ── CLI subprocess ────────────────────────────────────────────────────────────

class TestCLISubprocess:
    def test_help_exits_zero(self):
        result = subprocess.run(
            [sys.executable, str(CLI_DIR / "sawectl.py"), "--help"],
            capture_output=True, text=True
        )
        assert result.returncode == 0
        assert "sawectl" in result.stdout.lower() or "sawectl" in result.stderr.lower()

    def test_validate_workflow_on_sample(self):
        samples = list(SAMPLES_DIR.glob("*.yaml"))
        if not samples:
            pytest.skip("No sample workflows available")
        result = subprocess.run(
            [
                sys.executable, str(CLI_DIR / "sawectl.py"),
                "validate-workflow",
                "--workflow", str(samples[0]),
                "--modules",  str(MODULES_DIR),
            ],
            capture_output=True, text=True
        )
        assert result.returncode == 0
        assert "PASSED" in result.stdout


# ── Module manifest ───────────────────────────────────────────────────────────

class TestModuleManifest:
    def test_load_existing_module_manifest(self):
        manifest = sawectl.load_module_manifest(str(MODULES_DIR), "slack_module")
        assert manifest is not None
        assert "name" in manifest

    def test_load_nonexistent_module_returns_none(self):
        manifest = sawectl.load_module_manifest(str(MODULES_DIR), "does_not_exist")
        assert manifest is None
