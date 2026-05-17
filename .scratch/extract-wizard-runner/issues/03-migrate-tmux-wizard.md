# Migrate `install_tmux_wizard` onto the Wizard runner

Status: ready-for-agent

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
