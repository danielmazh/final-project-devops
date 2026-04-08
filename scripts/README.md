# scripts/

Build-time helper scripts for version management and change detection, used by Jenkins CI pipelines and available for local use.

## Files

```
scripts/
├── version.sh           # Read VERSION file, export APP_VERSION (23 lines)
└── change-detect.sh     # Git diff classifier → BUILD_ENGINE / BUILD_CLI (56 lines)
```

## version.sh

Reads the root `VERSION` file and exports `APP_VERSION` as an environment variable.

```bash
source scripts/version.sh
echo $APP_VERSION    # 0.1.2
```

Used by Jenkins pipelines to tag Docker images and git releases with the current semver.

## change-detect.sh

Analyzes `git diff HEAD~1` to classify which components changed, outputting boolean flags:

```bash
source scripts/change-detect.sh
echo "Engine: $BUILD_ENGINE  CLI: $BUILD_CLI"
```

**Path classification:**

| Changed path | Sets |
|-------------|------|
| `engine/`, `docker/engine/`, `engine/configuration/` | `BUILD_ENGINE=true` |
| `cli/`, `docker/cli/` | `BUILD_CLI=true` |
| `VERSION` | Both `BUILD_ENGINE=true` AND `BUILD_CLI=true` |
| Anything else | No flags set |

**In Jenkins:** The pipelines use an enhanced version of this logic with `GIT_PREVIOUS_SUCCESSFUL_COMMIT` as the diff base (instead of `HEAD~1`) to catch all changes since the last green build. See `jenkins/Jenkinsfile.engine` lines 32–49 for the Groovy implementation.

## Version Coupling

The `VERSION` file at the repo root is the single source of truth for semantic versioning. When it changes, both CI pipelines are triggered, ensuring engine and CLI always share the same version. This mechanism is detailed in the [Version Coupling section of the technical report](.cursor/reports/0001_final_project_technical_report.md#8-version-coupling-mechanism).
