# Wizard runner module + zsh tracer-bullet migration

Status: done

## Parent

`.scratch/extract-wizard-runner/PRD.md`

## What to build

Introduce the [[Wizard runner]] at `utils/wizard.sh` and prove it end-to-end by migrating the zsh installer to use it. After this slice lands, one module's full path through the new machinery (runner → `wizard_main` footer → `start_module_wizard` in `deploy.sh`) is demoable; the other four modules still use their old per-installer wizard plumbing and will be migrated by follow-up slices.

The runner exposes three helpers, all consumed by the zsh migration in this same slice:

- `wizard_run` — executes a step list as an `&&`-chain. With `-y` as the first arg, pipes `yes "\n"` into the chain so interactive prompts accept defaults; without it, leaves stdin alone. Short-circuits on the first failing step and preserves its exit code. Steps are passed positionally after a `--` separator so user flags and step names can't collide: `wizard_run "$@" -- step1 step2 step3`.
- `wizard_main` — the `--wizard` dispatch helper. Takes a wizard-function name plus the script's `"$@"`; invokes the function when `$1 = --wizard`, no-ops otherwise. Replaces every installer's trailing `if [ "$1" = --wizard ] ...` footer.
- `start_module_wizard` — the `deploy.sh`-side helper. Takes a module name and shells out to `sh -- "$DOTFILES/<name>/install_<name>.sh" --wizard`. The `sh --` subshell isolation is load-bearing: it ensures a `die` inside one module's wizard does not terminate `deploy_wizard`. Returns the subshell's exit code so the caller can decide what to do.

Wire the runner in by sourcing `utils/wizard.sh` from `utils/utils.sh` (next to the existing `managed_block.sh` / `pm_packages.sh` / `xdg_paths.sh` lines) so every installer already sourcing `utils.sh` picks it up transitively.

Migrate zsh as the proving module:

- Collapse `install_zsh_wizard` to a step list driven by `wizard_run "$@" -- install_zsh_program install_zsh_dotfiles set_zsh_as_default_shell`.
- Replace the trailing `if [ "$1" = --wizard ]` footer with `wizard_main install_zsh_wizard "$@"`.
- Drop the dead `interactive` literal that the old footer passed in.
- Replace the existing wizard-chain mock block in `zsh/test_install_zsh.sh` with the ~5-line "right step list is passed to `wizard_run`" assertion: spy on `wizard_run`, call `install_zsh_wizard`, assert on the argv.
- In `deploy.sh`: replace the `start_zsh_wizard` call site inside `deploy_wizard` with `start_module_wizard zsh`, and delete the `start_zsh_wizard` pass-through function. The four other `start_<mod>_wizard` functions stay for now — their owners will delete them in their own slices.

New `utils/test_wizard.sh` covers the runner at its interface:

- `wizard_run` calls steps in order.
- `wizard_run` short-circuits on the first failing step; later steps are not invoked.
- `wizard_run` preserves the failing step's exit code.
- `wizard_run -y` pipes `yes "\n"` into the chain (verified via a step that reads stdin).
- `wizard_run` without `-y` leaves stdin alone.
- `wizard_main` invokes its target when `$1 = --wizard`.
- `wizard_main` no-ops when `$1` is anything else, including empty.
- `start_module_wizard <name>` shells out to `sh -- "$DOTFILES/<name>/install_<name>.sh" --wizard` (verified by spying on `sh` and asserting on the argv).
- `start_module_wizard` returns the subshell's exit code.

Prior art for the test conventions: `utils/test_managed_block.sh` (pure transform tested directly) and `utils/test_utils.sh` (mocking external commands via shpy). No Docker required — the runner is pure composition.

## Acceptance criteria

- [ ] `utils/wizard.sh` exists and defines `wizard_run`, `wizard_main`, `start_module_wizard` following the repo's POSIX `sh` / 2-space / `snake_case` conventions.
- [ ] `utils/utils.sh` sources `utils/wizard.sh` alongside the other shared utilities.
- [ ] `utils/test_wizard.sh` exercises every behaviour listed under "What to build" using shunit2 + shpy.
- [ ] `zsh/install_zsh.sh`'s `install_zsh_wizard` reads as a step list passed to `wizard_run`, and the trailing footer is replaced by `wizard_main install_zsh_wizard "$@"`.
- [ ] `zsh/test_install_zsh.sh` no longer mocks the full `&&`-chain; it asserts on the argv `install_zsh_wizard` passes to `wizard_run` (≈5 lines).
- [ ] `deploy.sh` calls `start_module_wizard zsh` in place of `start_zsh_wizard`, and the `start_zsh_wizard` function is deleted. The other four `start_<mod>_wizard` pass-throughs remain untouched.
- [ ] `make lint` passes.
- [ ] `make unit` passes — including the new `utils/test_wizard.sh` and the modified `zsh/test_install_zsh.sh`.
- [ ] `make system-ubuntu` for the zsh system tests still passes; the wizard behaviour observed by a human running `deploy.sh` for the zsh module is unchanged.

## Blocked by

None - can start immediately

## Comments

### 2026-05-17 — landed on develop

- New `utils/wizard.sh` with `wizard_run`, `wizard_main`, `start_module_wizard` (POSIX sh, sourced via `utils/utils.sh`).
- `utils/test_wizard.sh` covers all 9 behaviours from the spec (order, short-circuit, exit-code preservation, `-y` stdin, no-`-y` stdin passthrough, `wizard_main` dispatch + no-op, `start_module_wizard` argv + exit code).
- `zsh/install_zsh.sh`: body is now `wizard_run "$@" -- install_zsh_program install_zsh_dotfiles set_zsh_as_default_shell`; footer is `wizard_main install_zsh_wizard "$@"`.
- `zsh/test_install_zsh.sh`: deleted the two old wizard-chain tests; replaced with a single `test_wizard_delegates_step_list_to_wizard_run` (~5 lines) asserting argv to `wizard_run`.
- `deploy.sh`: deleted `start_zsh_wizard`; `deploy_wizard` now calls `start_module_wizard zsh`. Other four `start_<mod>_wizard` pass-throughs untouched (slices 02-05 will delete them).

**Deviation from spec.** Spec says "spy on `sh`" in `utils/test_wizard.sh`. shpy generates spy executables with `#!/usr/bin/env sh` shebangs, so a `sh` spy on PATH recurses through env infinitely. Worked around by introducing a one-line `_sh()` wrapper in `wizard.sh` and spying on `_sh` in the test. Argv contract is preserved at the `_sh` boundary; production `sh --` semantics are unchanged.

**Pre-existing bug noticed.** `tests/test_deploy.sh` never spies on `start_asdf_wizard`, so running `make unit FILE=tests/test_deploy.sh` actually downloads asdf from GitHub during two of the four tests. Not introduced by this slice — was already broken. Worth a follow-up issue.

**Validation that passed.** `make lint`; `make unit FILE=utils/test_wizard.sh` (9/9); `make unit FILE=zsh/test_install_zsh.sh` (21/21); `make unit FILE=tests/test_deploy.sh` (4/4); `make system-ubuntu FILE=zsh/test_install_zsh.system.sh` (2/2).
