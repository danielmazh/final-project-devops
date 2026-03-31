# SeyoAWE Community — setup & fixes checklist

This file has **Part 1** (runtime setup), **Part 2** (remaining code/content follow-ups), and **Part 3** (documentation status).

---

## Part 1 — Mandatory setup & migration

Complete these so paths, the engine, and `sawectl` match how this repo is meant to run.

### `sawectl` alias (required for copy-paste)

From the **repository root**, define **`sawectl`** once per shell (see root **`README.md`**):

```bash
alias sawectl="$PWD/sawectl/binaries/linux/sawectl"   # Linux
# alias sawectl="$PWD/sawectl/binaries/macos.arm/sawectl"   # Apple Silicon
```

Checklist commands below assume this alias (or `PATH` including `sawectl/binaries/linux`).

### Layout: repo root as execution plane

- [ ] **Run the engine only from the repo root** — `./run.sh linux` (or `macos`) must be started in the same directory that contains `configuration/`, `modules/`, `workflows/`, and `seyoawe.linux`. All paths in `configuration/config.yaml` are relative to that working directory.

### `configuration/config.yaml`

- [ ] **Point `directories` at the local tree** (not nested `seyoawe-community/...` paths):
  - `workdir: .`
  - `modules: ./modules`
  - `workflows: ./workflows`
  - `lifetimes: ./lifetimes`
  - `logs: ./logs`
- [ ] **Set `app.customer_id`** to the customer segment used in API URLs: `POST /api/<customer_id>/<workflow_name>`. Workflows on disk live under `workflows/<customer_id>/<name>.yaml` (e.g. `workflows/default/...` when `customer_id` is `default`).

### Logging (verify it works)

- [ ] **`directories.logs: ./logs`** — Relative to the **repo root** (same cwd as `./run.sh`). The engine creates or appends files here (e.g. `workflow_engine.log`, `flask_app.log`, `lifetime_manager.log`, `command_module.log`, `approval_manager.log`).
- [ ] **`logging:` block** — `level` (e.g. `DEBUG` / `INFO`) and `format` apply to engine logging. Tune `level` if logs are too noisy.
- [ ] **Confirm logs update when you run workflows** — With the server running, trigger a workflow (`sawectl run` or `POST /api/<customer>/<workflow>`). Check `./logs/`: file **size** and **modification time** should change (e.g. `workflow_engine.log` grows). If not, the engine is probably started from the wrong directory or `./logs` is not writable.
- [ ] **`.gitignore` has `*.log`** — Log files stay local and are not committed; that is intentional.

### Modules directory

- [ ] **Keep every module package under `modules/<name>/`** — Each folder has `module.yaml`, Python entry, and any templates.
- [ ] **Create the engine path shim: `modules/modules` → `.`** — From inside `modules/`: `ln -s . modules` (skip if present). On Windows, use `mklink` / WSL.

### Webform UI (avoid a blank gray page)

The engine on **:8080** only serves the HTML shell; **JS/CSS** load from **:9000** by default (`t.webform.html` sets `<base href="…:9000/">`).

- [ ] **`cd modules/webform && ./link_assets.sh`** — Ensures `webform_bundle.js`, `custom.css`, and `configs/` are available next to `serve_webform_assets.py`.
- [ ] **`./run.sh linux`** from repo root now starts **`serve_webform_assets.py`** in the background on port **9000** (disable with **`WEBFORM_ASSETS=0`**). Or run `python3 modules/webform/serve_webform_assets.py` in another terminal.
- [ ] **Check:** `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9000/webform_bundle.js` should return **200**.

### Engine binaries (Linux / macOS)

- [ ] **`seyoawe.linux` / `seyoawe.macos.arm`** next to `run.sh`; `chmod +x` as needed.
- [ ] **Replace** the engine binary when your pipeline ships a new build.

### `sawectl` binary

- [ ] **Rebuild after CLI or schema changes:** `cd sawectl && ./build_cli.sh` (uses `sawectl/.venv`).
- [ ] **Build artifacts** stay out of git (`sawectl/build/`, etc.).

### `sawectl` logger example (end-to-end)

Run from **repo root**. Rebuild the binary after pulling `sawectl` changes.

- [ ] **`sawectl init module logger`** — Fails if `modules/logger` already exists (expected).
- [ ] **`sawectl init workflow hello_logger --full --modules logger`** → **`workflows/default/hello_logger.yaml`**
- [ ] **`sawectl validate-workflow --workflow workflows/default/hello_logger.yaml`**
- [ ] **Engine + run:** `./run.sh linux` then **`sawectl run --workflow workflows/default/hello_logger.yaml --server localhost:8080`**

---

## Part 2 — Remaining fixes (optional / environment-specific)

### If you add `slack_module`

- [ ] **`module.yaml` / `usage_reference.yaml`** match **`slack.py`** (`class Slack`, `send_info_message`, …). Remove conflicting stub `slack_module.py` if present.

### Samples & snippets

- [ ] **`workflows/default/samples/command_and_slack.yaml`** — Requires a real **`slack_module`**; validate only when that package is installed and manifests are correct.
- [ ] **`workflows/default/samples/global_failure_handler.yaml`** — Illustrative `...` placeholders; not a runnable file as-is.
- [ ] **`workflows/default/samples/modules/*.yaml`** — Multi-document **fragments**; wrap in a full `workflow:` or use as docs only.

### Repo hygiene

- [ ] **Dedupe** `.gitignore` line for `sawectl/distribute.egg-info/` if duplicated.
- [ ] **Nested duplicate `seyoawe-community/`** tree — remove or document if accidental.
- [ ] **`app.customer_id` vs `module_dispatcher.customer_id`** — Confirm `default` vs `community` for your deployment.

### Quick validation (when modules match)

```bash
sawectl validate-workflow --workflow workflows/default/hello-world.yaml
sawectl validate-workflow --workflow workflows/default/hello_logger.yaml
```

---

## Part 3 — README & examples (maintained)

Aligned README pass: root **`README.md`**, **`sawectl/README.md`**, and **`modules/*/README.md`** use:

- Repo-relative paths (`modules/…`, `configuration/config.yaml`, `workflows/default/…`)
- **`sawectl init workflow`** / **`init module`** (not old `workflow init` / `module create`)
- **`sawectl`** command (after **`alias`** from root README) from repo root
- Action DSL: **`type: action`** + **`package.Class.method`**
- **`logger`** / **`command_module`** for copy-paste where **`slack_module`** is not shipped
- **`command_module`:** **`working_dir` / `run_as_user`** supported as aliases of **`cwd` / `user`** (see `command.py` + `module.yaml`)
- **`workflows/default/hello-world.yaml`** matches the root README and validates

- [x] **Root `README.md`** — Quickstart, triggers, module table, typos fixed
- [x] **`sawectl/README.md`** — Commands, `build_cli.sh`, paths
- [x] **`modules/api_module/README.md`** — API response shape, example without Slack
- [x] **`modules/chatbot_module/README.md`** — `context.<step>.data.reply`
- [x] **`modules/command_module/README.md`** — Parameters + `exit_code` in output
- [x] **`modules/email_module/README.md`** — `configuration/config.yaml`, templates path
- [x] **`modules/git_module/README.md`** — `modules/git_module/` paths
- [x] **`modules/webform/README.md`** — `modules/webform/`, logger placeholders for notifications

---

## Reference

| Artifact | Notes |
|----------|--------|
| `command_and_slack.yaml` | Needs **`slack_module`** + valid Slack manifest |
| `hello_logger.yaml` / `hello-world.yaml` | Valid with bundled **`logger`** module |