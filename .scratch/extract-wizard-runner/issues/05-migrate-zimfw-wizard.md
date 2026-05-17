# Migrate `install_zimfw_wizard` onto the Wizard runner

Status: done

## Parent

`.scratch/extract-wizard-runner/PRD.md`

## What to build

Move `zimfw/install_zimfw.sh` onto the [[Wizard runner]]. The wrinkle that makes this its own slice is `check_zsh_prerequisites`: it is a hard precondition (e.g. "zsh not installed. Run zsh/install_zsh.sh --wizard first."), not a step the chain can short-circuit on, so it must run before the step list executes.

Two valid placements; pick one:

- **Pre-call** — call `check_zsh_prerequisites` inside `install_zimfw_wizard` before invoking `wizard_run`. Reads as "preconditions then chain"; keeps the runner's interface a flat step list.
- **First step** — make `check_zsh_prerequisites` (or a thin no-arg wrapper around it) the first entry in the step list. Relies on the fact that the chain short-circuits and preserves exit codes, so a failing precondition still terminates the wizard with the same diagnostic.

Whichever placement is chosen, the existing diagnostic messages (`zsh not installed...`, `$HOME/.zshenv missing...`, `$zdotdir/.zshrc missing...`) must surface verbatim when the precondition fails.

The rest of the migration is the standard shape:

- Collapse the body to a `wizard_run "$@" -- <step list>` call (after the precondition, or with it as step one).
- Replace the trailing footer with `wizard_main install_zimfw_wizard "$@"`. Drop the dead `interactive` literal.

Test surface:

- Delete the existing wizard-chain mock block in `zimfw/test_install_zimfw.sh`.
- Add the per-module ~5-line assertion: spy on `wizard_run`, call `install_zimfw_wizard`, assert on the argv.
- Add or keep a test asserting the precondition still fires and emits its diagnostic when zsh/zshenv/zshrc are missing — whichever placement makes that easiest.

`deploy.sh`:

- Replace `start_zimfw_wizard` call inside `deploy_wizard` with `start_module_wizard zimfw`.
- Delete the `start_zimfw_wizard` pass-through function. After this slice all five `start_<mod>_wizard` pass-throughs are gone and the PRD's `deploy.sh`-side goal is complete.

## Acceptance criteria

- [ ] `install_zimfw_wizard` is reduced to a precondition call + `wizard_run` (or `wizard_run` with the precondition as step one), whichever placement is chosen.
- [ ] All three existing precondition diagnostics surface verbatim when their condition is unmet.
- [ ] Trailing footer replaced by `wizard_main install_zimfw_wizard "$@"`.
- [ ] `zimfw/test_install_zimfw.sh` no longer mocks the full chain; it asserts on the argv passed to `wizard_run` and still covers the precondition's failure path.
- [ ] `deploy.sh` calls `start_module_wizard zimfw`; the `start_zimfw_wizard` function is deleted.
- [ ] No `start_<mod>_wizard` pass-through functions remain in `deploy.sh` after this slice merges.
- [ ] `make lint` passes.
- [ ] `make unit FILE=zimfw/test_install_zimfw.sh` passes.
- [ ] `make system-ubuntu` for the zimfw system tests still passes.

## Blocked by

- `.scratch/extract-wizard-runner/issues/01-wizard-runner-and-zsh-migration.md`

## Comments

### 2026-05-17 — landed on develop

- `zimfw/install_zimfw.sh`: `install_zimfw_wizard` now runs `check_zsh_prerequisites || return $?` then `wizard_run "$@" -- install_zimfw_program install_zimfw_dotfiles install_zimfw_modules`. **Placement choice:** pre-call. Reads as "preconditions then chain" and keeps the runner's step list pure (only real install steps). The three precondition diagnostics surface verbatim — they're emitted by `check_zsh_prerequisites` itself, unchanged. Footer is `wizard_main install_zimfw_wizard "$@"`.
- `zimfw/test_install_zimfw.sh`: deleted the three chain-mock wizard tests; added `test_wizard_aborts_when_preconditions_fail` and `test_wizard_delegates_step_list_to_wizard_run`. The existing `test_preconditions_die_if_*` tests stay — they cover the precondition's diagnostic output, which the wizard tests don't duplicate.
- `zimfw/test_install_zimfw.system.sh`: added `# shellcheck disable=SC2119` on the `install_zimfw_wizard` no-arg call (same pattern other migrated tests use).
- `deploy.sh`: deleted `start_zimfw_wizard`; `deploy_wizard` calls `start_module_wizard zimfw`. No `start_<mod>_wizard` pass-throughs remain — the PRD's `deploy.sh`-side goal is now complete.
- `tests/test_deploy.sh`: all-yes tests now assert `start_module_wizard 5` (zsh, zimfw, asdf, tmux, git) with `assertCalledWith` in that order. Dropped `start_zimfw_wizard` spies/asserts.

**Validation that passed.** `make lint`; `make unit FILE=zimfw/test_install_zimfw.sh` (15/15); `make unit FILE=tests/test_deploy.sh` (4/4); `make system-ubuntu FILE=zimfw/test_install_zimfw.system.sh` (2/2).
