# Migrate `install_tmux_wizard` onto the Wizard runner

Status: done

## Parent

`.scratch/extract-wizard-runner/PRD.md`

## What to build

Move `tmux/install_tmux.sh` onto the [[Wizard runner]]. This is the slice that exercises the documented "wrap a parameterized step as a no-arg step" convention, because `install_tmux_program` takes a `"$desired_version"` argument today.

- Introduce `install_tmux_program_step` (or equivalent no-arg name) as a thin wrapper around `install_tmux_program "$desired_version"`. The desired-version constant (`3.1b` today) moves into that wrapper. `wizard_run`'s interface stays a flat list of function names — no `eval`, no closures.
- Collapse `install_tmux_wizard` to `wizard_run "$@" -- <step list with install_tmux_program_step in the right slot>`. The order of steps and their externally observable behaviour is unchanged.
- Replace the trailing footer with `wizard_main install_tmux_wizard "$@"`. Drop the dead literal arg the old footer passed in.

Test surface:

- Delete the existing wizard-chain mock block in `tmux/test_install_tmux.sh`.
- Add the per-module ~5-line assertion: spy on `wizard_run`, call `install_tmux_wizard`, assert on the argv (the step list including `install_tmux_program_step`).
- If a step-function test for `install_tmux_program_step` is warranted, add a single-line test that it forwards to `install_tmux_program` with the expected version constant. Existing step-function tests for `install_tmux_program` itself remain unchanged.

`deploy.sh`:

- Replace `start_tmux_wizard` call inside `deploy_wizard` with `start_module_wizard tmux`.
- Delete the `start_tmux_wizard` pass-through function.

## Acceptance criteria

- [ ] `install_tmux_program_step` exists as a no-arg wrapper forwarding to `install_tmux_program` with the desired-version constant.
- [ ] `install_tmux_wizard` body is a single `wizard_run` call whose step list includes `install_tmux_program_step` in the same position the parameterized call held before.
- [ ] Trailing footer replaced by `wizard_main install_tmux_wizard "$@"`.
- [ ] `tmux/test_install_tmux.sh` no longer mocks the full chain; it asserts on the argv passed to `wizard_run`.
- [ ] `deploy.sh` calls `start_module_wizard tmux`; the `start_tmux_wizard` function is deleted.
- [ ] `make lint` passes.
- [ ] `make unit FILE=tmux/test_install_tmux.sh` passes.
- [ ] `make system-ubuntu` for the tmux system tests still passes; the installed tmux version is still `3.1b`.

## Blocked by

- `.scratch/extract-wizard-runner/issues/01-wizard-runner-and-zsh-migration.md`

## Comments

### 2026-05-17 — landed on develop

- `tmux/install_tmux.sh`: added `install_tmux_program_step` no-arg wrapper next to `install_tmux_program`; the `3.1b` desired-version constant lives in the wrapper. `install_tmux_wizard` body is now `wizard_run "$@" -- install_tmux_program_step install_tmux_dotfiles install_tpm install_tpm_plugins install_tmux_shell_bridge`; footer is `wizard_main install_tmux_wizard "$@"`.
- `tmux/test_install_tmux.sh`: deleted the two old chain-mock wizard tests; added `test_install_tmux_program_step_forwards_pinned_version` (asserts `install_tmux_program 3.1b`) and `test_wizard_delegates_step_list_to_wizard_run`.
- `deploy.sh`: deleted `start_tmux_wizard`; `deploy_wizard` calls `start_module_wizard tmux`.
- `tests/test_deploy.sh`: `start_module_wizard` is now called 3 times in the all-yes tests (zsh, tmux, git) and 2 times in the zsh-declined test (tmux, git); ordered `assertCalledWith` updated accordingly.

**Validation that passed.** `make lint`; `make unit FILE=tmux/test_install_tmux.sh` (31/31); `make unit FILE=tests/test_deploy.sh` (4/4); `make system-ubuntu FILE=tmux/test_install_tmux.system.sh` (7/7).
