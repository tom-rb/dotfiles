# Module skeleton + pi program install

Status: ready-for-agent

## What to build

The walking skeleton for a new `pi` [[Module]] (the pi coding agent) plus the path that installs the pi program itself, end to end.

pi is a global npm package (`@earendil-works/pi-coding-agent`) running on Node, so the program install must first ensure a Node runtime, then `npm i -g` a pinned version, then refresh the asdf shim when Node is asdf-managed.

Scope:

- A shared `ensure_node` helper (new `utils/runtime.sh`, sourced from `utils/utils.sh`): reuse `node` if already on `PATH`; else if `asdf` is present, add+install the `nodejs` plugin (latest); else `install_from_pm`. Keeps the pi module asdf-agnostic — the util owns the asdf knowledge.
- `get_pi_config_dir()` in `utils/xdg_paths.sh`, echoing `${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}` (mirrors pi's own resolution; pi owns its non-XDG layout).
- `pi/install_pi.sh` exposing `install_pi_wizard` via `wizard_main`, with an `install_pi_program` step: `ensure_node`, then `npm install -g @earendil-works/pi-coding-agent@$PI_VERSION` (pinned `PI_VERSION` constant), then `command_exists asdf && asdf reshim nodejs`. Guard with `is_pi_installed` (`command_exists pi`) so re-runs are quiet.
- An `"Install pi?"` prompt added to `deploy_wizard` in `deploy.sh`.

Follow repo conventions: POSIX `sh`, 2-space indent, the `THISDIR` self-location pattern, subshell + `set -e` for the install flow, `die` for errors, one short comment per function.

## Acceptance criteria

- [ ] `sh pi/install_pi.sh --wizard` on a clean host ensures Node and installs pi; `pi` resolves on `PATH` afterward
- [ ] Re-running the wizard with pi already present is idempotent and quiet (no reinstall)
- [ ] `ensure_node` reuses an existing `node`, falls back to asdf when present, then to the package manager — verified with mocked `node`/`asdf`/PM in unit tests
- [ ] `get_pi_config_dir()` honors `PI_CODING_AGENT_DIR` and defaults to `$HOME/.pi/agent`
- [ ] `deploy.sh` offers an "Install pi?" prompt that delegates to the pi wizard
- [ ] Unit tests (`pi/test_install_pi.sh`, shunit2 + shpy) mock npm/asdf/PM; a system test (`pi/test_install_pi.system.sh`, with an `# @image:` annotation) installs pi for real

## Blocked by

None - can start immediately
