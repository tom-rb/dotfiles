# Migrate `install_git_wizard` onto the Wizard runner

Status: ready-for-agent

## Parent

`.scratch/extract-wizard-runner/PRD.md`

## What to build

Move `git/install_git.sh` onto the [[Wizard runner]] from slice 01. The git wizard is the only one that does not currently support `-y`; this migration closes that drift by handing `-y` plumbing to the runner.

- Collapse `install_git_wizard` so its body is a single `wizard_run "$@" -- <step1> <step2> ...` call. The step list is whatever steps the current `&&`-chain calls, in the same order — composition is the only thing changing.
- Replace the trailing `if [ "$1" = --wizard ]; then install_git_wizard; fi` footer with `wizard_main install_git_wizard "$@"`. Drop the dead literal that the footer passed in, if any.
- The runner is sourced transitively via `utils/utils.sh` (already wired in slice 01); no new source line in `install_git.sh`.

Test surface:

- Delete the existing wizard-chain mock block at `git/test_install_git.sh:180-260` (the `&&`-chain composition is now the runner's responsibility, covered by `utils/test_wizard.sh`).
- Add the per-module ~5-line assertion: spy on `wizard_run`, call `install_git_wizard`, assert on the argv (i.e. the step list and order).
- Step-function tests and `is_git_installed` seam tests (ADR-0001) are unchanged.

`deploy.sh`:

- Replace the `start_git_wizard` call inside `deploy_wizard` with `start_module_wizard git`.
- Delete the `start_git_wizard` pass-through function.

## Acceptance criteria

- [ ] `install_git_wizard` body is a single `wizard_run` call with the step list.
- [ ] Trailing footer replaced by `wizard_main install_git_wizard "$@"`.
- [ ] `git/install_git.sh --wizard -y` runs the chain non-interactively (gained capability — currently absent).
- [ ] `git/test_install_git.sh` no longer mocks the full chain; it asserts on the argv passed to `wizard_run`.
- [ ] `deploy.sh` calls `start_module_wizard git`; the `start_git_wizard` function is deleted.
- [ ] `make lint` passes.
- [ ] `make unit FILE=git/test_install_git.sh` passes.
- [ ] `make system-ubuntu` for the git system tests still passes; prompts and outputs are unchanged under the default (no-`-y`) path.

## Blocked by

- `.scratch/extract-wizard-runner/issues/01-wizard-runner-and-zsh-migration.md`
