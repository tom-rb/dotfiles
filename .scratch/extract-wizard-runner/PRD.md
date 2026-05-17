# Extract a Wizard runner: deepen the wizard pattern into a single shared module

Status: ready-for-agent

## Problem Statement

Every installer in this repo (`zsh/`, `git/`, `tmux/`, `asdf/`, `zimfw/`) reinvents the same Wizard plumbing in three places:

- **Layer A** — the body of `install_<mod>_wizard`: the `-y`/`yes`-pipe and the `&&`-chain of steps, duplicated verbatim in 4 of 5 installers.
- **Layer B** — the dispatch footer at the bottom of every installer: `if [ "$1" = --wizard ]; then install_<mod>_wizard ...; fi`, duplicated in 5 installers.
- **Layer C** — the cross-module `start_<mod>_wizard` pass-throughs in `deploy.sh`: 5 one-line functions each shelling out to a module installer.

Locality for the Wizard concept is zero: a change to how `-y` is plumbed, or to how `--wizard` is dispatched, requires touching every installer. The `install_git_wizard` has no `-y` support at all — drift the deep module would prevent. Per-module wizard tests (e.g. `git/test_install_git.sh:180-260`) spend ~80 lines mocking every step and asserting on `&&`-chain semantics — testing wizard composition through the wrong surface.

## Solution

Extract a **Wizard runner** module at `utils/wizard.sh` that owns the Wizard machinery. Each per-module `install_<mod>_wizard` becomes a thin adapter naming a list of [[Wizard step]]s; the runner handles `-y`, the chain, and the `--wizard` dispatch. `deploy.sh` calls a single `start_module_wizard <name>` helper instead of five named pass-throughs.

After this change:

- One place defines `-y` semantics.
- One place defines `--wizard` dispatch.
- One place defines the `sh --` subshell isolation contract that protects `deploy.sh` from a module's `die`.
- Each installer's wizard collapses to a step list — the only per-module thing the runner needs to know.

Vocabulary already landed in `CONTEXT.md`: `Wizard`, `Wizard step`, `Wizard runner`.

## User Stories

1. As a dotfiles maintainer, I want the `-y` plumbing in one place, so that I don't have to keep four copies of the same `yes "…" | { … }` snippet in sync.
2. As a dotfiles maintainer, I want every wizard to support `-y` by default, so that the `install_git_wizard` drift (no `-y`) can't happen again silently.
3. As a dotfiles maintainer, I want the `--wizard` dispatch footer in one place, so that changing how scripts are invoked is a one-line edit.
4. As a dotfiles maintainer, I want `deploy.sh` to dispatch to module wizards via a single named helper, so that adding a new module doesn't require defining a new `start_<mod>_wizard` pass-through.
5. As a dotfiles maintainer, I want each `install_<mod>_wizard` function to read as a step list, so that a reader can see at a glance which steps run, in which order.
6. As a contributor adding a new module, I want a single line at the bottom of my installer (`wizard_main install_<mod>_wizard "$@"`), so that I don't reinvent the dispatch boilerplate.
7. As a contributor adding a new step to an existing wizard, I want to append a function name to a list, so that the change is local and obvious.
8. As a contributor writing a step that needs an argument, I want a documented convention for wrapping it as a no-arg step, so that the runner interface stays simple.
9. As an `install_tmux_wizard` user, I want the `install_tmux_program` step to still receive `"$desired_version"`, so that the tmux wizard behaves identically to today.
10. As a `deploy_wizard` user, I want a failing module install to NOT terminate `deploy.sh`, so that I can choose to skip a broken module and continue with the rest.
11. As an `install_zimfw_wizard` user, I want the `check_zsh_prerequisites` precondition to run before the step chain, so that I still get a clear error when zsh hasn't been installed first.
12. As a test author, I want one place to test `-y` semantics (`utils/test_wizard.sh`), so that I don't have to add a near-identical test in every installer's test file.
13. As a test author, I want each `test_install_<mod>.sh` to assert that the right step list is passed to the runner, so that the per-module contract is still verified — but in 5 lines, not 80.
14. As a test author, I want `wizard_run` to be testable through its interface (step list + `-y` flag), so that the test surface matches the runner's interface.
15. As a test author, I want `start_module_wizard <name>` to be verifiable as shelling out under a fresh `sh --`, so that the subshell isolation contract is documented in code, not folklore.
16. As a reviewer, I want vocabulary in CONTEXT.md (`Wizard`, `Wizard step`, `Wizard runner`) that matches the code, so that PR discussions use consistent language.
17. As a wizard end-user (the human running `deploy.sh`), I want behaviour to be unchanged — same prompts, same `-y` behaviour, same dispatch — so that this refactor is invisible to me.

## Implementation Decisions

### Modules

- **NEW `utils/wizard.sh`** — the deepened Wizard runner. Exposes three helpers:
  - `wizard_run` — executes a step list as an `&&`-chain. When invoked with `-y`, pipes `yes "\n"` into the chain so interactive prompts accept defaults. Without `-y`, leaves stdin alone. Short-circuits on the first failing step; preserves its exit code.
  - `wizard_main` — the `--wizard` dispatch helper. Takes a wizard-function name and the script's `"$@"`; invokes the function when `$1 = --wizard`, no-ops otherwise. Replaces the trailing footer in every installer.
  - `start_module_wizard` — the `deploy.sh`-side helper. Takes a module name, shells out to `sh -- "$DOTFILES/<name>/install_<name>.sh" --wizard`. The subshell isolation is load-bearing: it ensures a `die` in one module's wizard doesn't terminate `deploy_wizard`.
- **MODIFY `utils/utils.sh`** — source `utils/wizard.sh` alongside the existing `managed_block.sh` / `pm_packages.sh` / `xdg_paths.sh` lines, so every installer that sources `utils.sh` picks the runner up transitively.
- **MODIFY `deploy.sh`** — delete the 5 `start_<mod>_wizard` pass-through functions. Replace each call site in `deploy_wizard` with `start_module_wizard <name>`.
- **MODIFY `zsh/install_zsh.sh`** — collapse `install_zsh_wizard`'s body to `wizard_run "$@" -- install_zsh_program install_zsh_dotfiles set_zsh_as_default_shell`. Replace the trailing `if [ "$1" = --wizard ] ...` footer with `wizard_main install_zsh_wizard "$@"`.
- **MODIFY `git/install_git.sh`** — collapse `install_git_wizard` to the same shape (gains `-y` support for free, currently absent). Replace footer with `wizard_main install_git_wizard "$@"`.
- **MODIFY `tmux/install_tmux.sh`** — collapse `install_tmux_wizard` to the runner-driven shape. Because `install_tmux_program` takes `"$desired_version"` (currently `3.1b`), wrap it as a no-arg `install_tmux_program_step`. The desired-version constant moves into that wrapper. Replace footer with `wizard_main install_tmux_wizard "$@"`.
- **MODIFY `asdf/install_asdf.sh`** — same shape.
- **MODIFY `zimfw/install_zimfw.sh`** — same shape, with one caveat: `check_zsh_prerequisites` must still run before the step chain (it's a hard precondition, not a step the chain can short-circuit on). Either keep it inside `install_zimfw_wizard` before the `wizard_run` call, or make it the first step in the list — leaving the choice to the implementer; the precondition's diagnostic message must still surface verbatim.

### Interface conventions

- **Wizard steps are no-arg functions.** Modules that need to parameterize a step wrap it in a no-arg step function (e.g. `install_tmux_program_step`). This keeps `wizard_run`'s interface a flat list of function names — no `eval`, no closure tricks.
- **`-y` is the only flag.** The runner accepts `-y` as `$1`; anything else is treated as interactive. The current `install_zsh_wizard interactive` arg is a vestige and disappears.
- **Step list is passed positionally after a `--` separator** (`wizard_run "$@" -- step1 step2 step3`), so the runner can distinguish user-passed flags from step names.
- **Subshell isolation in `start_module_wizard`** is a documented contract, not a side effect. The helper must use `sh --` (not source).

### Vocabulary (already landed in CONTEXT.md)

- **Wizard** — the user-facing install flow for a module; a list of [[Wizard step]]s composed by the [[Wizard runner]].
- **Wizard step** — one function in a wizard's chain; no-arg by convention.
- **Wizard runner** — `utils/wizard.sh`, the shared machinery; exposes `wizard_run`, `wizard_main`, `start_module_wizard`.

### Architectural notes

- This is a **dependency category 1** deepening (in-process pure composition, no I/O, no ports/adapters). The runner is testable directly through its interface; no in-memory adapter needed.
- ADR-0001 (keep `is_<prog>_installed` wrappers) is untouched — those seams stay.
- ADR-0002 (asdf from tarball) is untouched.
- No new ADR needed: the design decisions are recorded in CONTEXT.md vocabulary; future "why is the wizard a runner?" questions are answered by reading the glossary.

## Testing Decisions

### What makes a good test here

Test through the interface, not past it. The Wizard runner's interface is: a step list, optionally preceded by `-y`. Tests assert on **observable behaviour** crossing that interface: which steps were called, in what order, with what exit code, what stdin they saw. Tests do not assert on internal state of the runner.

Per `writing-tests/SKILL.md`, tests follow shunit2 + shpy conventions; spies via `createSpy`; cleanup in `tearDown` via `cleanupSpies`; the runner's tests do not need Docker (in-process logic only, no system side effects).

### NEW — `utils/test_wizard.sh`

Tests at the runner's interface:

- `wizard_run` calls steps in order.
- `wizard_run` short-circuits on the first failing step; subsequent steps are not invoked.
- `wizard_run` preserves the exit code of the failing step.
- `wizard_run -y` pipes `yes "\n"` into the chain (verified via a step that reads stdin).
- `wizard_run` without `-y` leaves stdin alone.
- `wizard_main` invokes its target function when `$1 = --wizard`.
- `wizard_main` does nothing when `$1` is anything else (including empty).
- `start_module_wizard <name>` shells out to `sh -- "$DOTFILES/<name>/install_<name>.sh" --wizard` (verified by spying on `sh` and asserting on the argv).
- `start_module_wizard` returns the subshell's exit code so `deploy_wizard` can decide what to do.

Prior art for the test conventions: `utils/test_managed_block.sh` (pure transform tested directly), `utils/test_utils.sh` (tests that mock external commands via shpy).

### MODIFIED — per-module test files (`*/test_install_<mod>.sh`)

Existing tests:

- Step-function tests (`test_install_<mod>_program`, `test_install_<mod>_dotfiles`, …) — **unchanged**. Each step is still tested at its own interface.
- `is_<mod>_installed` seam tests (ADR-0001) — **unchanged**.

Wizard-level tests collapse:

- **Delete** the existing wizard-chain mock blocks (e.g. `git/test_install_git.sh:180-260` and similar in zsh/asdf/zimfw/tmux). They are now redundant with `utils/test_wizard.sh`.
- **Add** a tiny per-module test that verifies the right step list is passed to `wizard_run`. Roughly five lines: spy on `wizard_run`, call `install_<mod>_wizard`, assert on the argv received. This is the per-module contract that the runner-level tests cannot cover.

### Out of test scope

- `deploy.sh` itself does not gain a new test. `start_module_wizard` is tested in `utils/test_wizard.sh`; `deploy.sh`'s use of it is wiring, not logic.
- System tests (`test_*.system.sh`) are unaffected — they exercise full install flows in Docker and should continue to pass unchanged. If they do not, that is a regression in the refactor, not in their design.

## Out of Scope

- The other deepening candidates surfaced during the architecture review (`install_<prog>_program` skip-if-present pattern; idempotent owned-state writer shared by `set_git_global_config` and `install_managed_block`; managed-block-render scaffold duplication; `echo "****"` banner triplets). Each can be its own future PRD.
- Adding `-n` (default-no) or any flag other than `-y`. The runner accepts `-y` only, matching today's behaviour.
- Replacing the `sh --` subshell isolation in `start_module_wizard` with sourcing. The isolation is load-bearing and stays.
- Changing how individual steps work, what they print, or what they prompt for. The refactor is composition-only.
- Touching ADR-0001 or ADR-0002.
- Backwards compatibility shims: this is a closed dotfiles repo with one user — no external callers depend on `start_<mod>_wizard` being importable. The 5 pass-through functions get deleted, not deprecated.

## Further Notes

- The grilling that produced these decisions is captured implicitly in the CONTEXT.md vocabulary update. Future architecture reviews that re-surface "wizard composition" as a candidate will find it already done.
- The `git/install_git.sh` wizard gains `-y` support as a side effect of the refactor. This is intentional — the asymmetry was a drift bug the deep module prevents.
- The `interactive` literal argument currently passed to `install_zsh_wizard` / `install_tmux_wizard` / `install_asdf_wizard` / `install_zimfw_wizard` from their footers is dead today (it just doesn't equal `-y`, so the else branch runs). It disappears under the new shape; the new wizard_main only forwards `--wizard` and the explicit `-y` flag if present.
- After this lands, the four "deepening candidates" report becomes a useful baseline for the next architecture pass. Worth re-running the review after to see how locality improved.
