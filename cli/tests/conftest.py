import sys
from pathlib import Path

# Add cli/ to sys.path so tests can import sawectl directly
CLI_DIR = Path(__file__).parent.parent
sys.path.insert(0, str(CLI_DIR))

# Shared path constants available to all test modules
REPO_ROOT    = CLI_DIR.parent
SCHEMAS_DIR  = CLI_DIR
SAMPLES_DIR  = REPO_ROOT / "engine" / "workflows" / "samples"
MODULES_DIR  = REPO_ROOT / "engine" / "modules"
VERSION_FILE = REPO_ROOT / "VERSION"
