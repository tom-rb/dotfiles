# Migrate `install_asdf_wizard` onto the Wizard runner

Status: ready-for-agent

## Parent

`.scratch/extract-wizard-runner/PRD.md`

## What to build

Move `asdf/install_asdf.sh` onto the [[Wizard runner]]. Same shape as the zsh migration in slice 01 — no parameterized steps, no preconditions.

- Collapse `install_asdf_wizard` to a single `wizard_run "$@" -- <step list>` call. Steps and order are unchanged from today's `&&`-chain.
- Replace the trailing footer with `wizard_main install_asdf_wizard "$@"`. Drop the dead `interactive` literal the old footer passed in.

Test surface:

- Delete the existing wizard-chain mock block in `asdf/test_install_asdf.sh`.
- Add the per-module ~5-line assertion: spy on `wizard_run`, call `install_asdf_wizard`, assert on the argv.
- Step-function tests and ADR-0002-related tests (asdf from tarball) are unchanged.

`deploy.sh`:

- Replace `start_asdf_wizard` call inside `deploy_wizard` with `start_module_wizard asdf`.
- Delete the `start_asdf_wizard` pass-through function.

## Acceptance criteria

- [ ] `install_asdf_wizard` body is a single `wizard_run` call with the step list.
- [ ] Trailing footer replaced by `wizard_main install_asdf_wizard "$@"`.
- [ ] `asdf/test_install_asdf.sh` no longer mocks the full chain; it asserts on the argv passed to `wizard_run`.
- [ ] `deploy.sh` calls `start_module_wizard asdf`; the `start_asdf_wizard` function is deleted.
- [ ] `make lint` passes.
- [ ] `make unit FILE=asdf/test_install_asdf.sh` passes.
- [ ] `make system-ubuntu` for the asdf system tests still passes.

## Blocked by

- `.scratch/extract-wizard-runner/issues/01-wizard-runner-and-zsh-migration.md`
