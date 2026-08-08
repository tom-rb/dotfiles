# Domain Language

This file is the glossary for the dotfiles repo. When code or docs name a concept, it should use the term defined here. New terms get added before (or as) they're used.

## Module

A per-tool slice of the repo — `git/`, `tmux/`, `zsh/`, `zimfw/`, `asdf/`, plus shared infrastructure under `utils/`. A module owns its configuration files, its install script, and its tests. Modules are self-contained: they source `utils/utils.sh` for shared helpers and otherwise know nothing about each other.

## Lifecycle directory

`lifecycle/` — **not a [[Module]]**, and deliberately has no `install_lifecycle.sh`. It holds the code behind the repo's top-level entry points: what `deploy.sh` (and later `update.sh`) needs that no module does. `lifecycle/deploy_profile.sh` is the first tenant, along with the tests for both it and `deploy.sh` itself.

The distinction from `utils/` is who pays for it. Everything in `utils/` is sourced by `utils/utils.sh`, which every module installer loads — so a file belongs there only if a module might plausibly want it. The deploy profile is used by exactly one caller, and lives here so `install_tmux.sh` does not carry it.

One consequence: `confirm -k` in `utils/tui.sh` reaches for `answer_for` and `record_answer`, which are *not* loaded in a module installer. Both calls are guarded, so an unkeyed `confirm` works everywhere and `-k` only functions where `deploy_profile.sh` has been sourced.

## Wizard

The user-facing install flow for a module, exposed as `install_<module>_wizard` and triggered by `sh <module>/install_<module>.sh --wizard`. A wizard is a list of [[Wizard step]]s composed by the [[Wizard runner]] into an `&&`-chain, with `-y` accepting default answers for every interactive prompt. The per-module `install_<module>_wizard` function is the adapter: it names the step list, the runner does everything else.

## Wizard step

One function in a wizard's chain — typically a program install, a dotfile render, or a post-install hook (e.g. `install_zsh_program`, `install_zsh_dotfiles`, `set_zsh_as_default_shell`). Steps are no-arg by convention; modules that need to parameterize a step (e.g. `install_tmux_program "$desired_version"`) wrap the call in a no-arg step function. The runner short-circuits on the first step that returns non-zero.

## Wizard runner

`utils/wizard.sh` — the shared machinery behind every wizard. Exposes two helpers: `wizard_run` (executes a step list, handles `-y` by piping `yes` into the chain) and `wizard_main` (the `--wizard` dispatch at the bottom of each installer script). Cross-module orchestration in `deploy.sh` uses `start_module_wizard <name>`, which shells out to the module's install script under a fresh `sh -- ` so a `die` in one module doesn't terminate the surrounding `deploy_wizard`.

## Task

One line of terminal output representing a unit of work: an open state ("→ installing zsh…") rewritten in place by exactly one [[Outcome]]. `tui_task` opens a task, runs a command, and closes it — callers never close a task themselves. Several tasks make up one [[Wizard step]].

## Outcome

How a [[Task]] ends: ok (✓), skip (•), warn (!) or fail (✗). Chosen by `tui_task` from the command's exit status and the `--ok` / `--die` / `--fail` / `--warn` wording it was given.

## Owned dotfile

A configuration file in the user's home (or `$ZDOTDIR`, `$XDG_CONFIG_HOME`, etc.) that the user owns but the dotfiles repo wants to write into. The user may have hand-rolled content there from before they installed the dotfiles — overwriting it blindly is hostile.

## Owned entry

One item a [[Module]] installs into a directory it shares with the user — a skill directory, or a rule file. The repo can prove it put that item there. The proof is a symlink whose target resolves inside one of the source directories that feed *that* destination. `utils/skills.sh::is_owned_entry` makes that test. The test covers only the sources that feed the destination, not `$DOTFILES` as a whole. So a link the user wires from some other corner of the checkout stays theirs. One example: a claude skill pulled into pi's directory, which this repo deliberately does not install there. When the repo stops shipping an entry, the installer removes it only if the repo owns it. A skill the user installed from anywhere else survives every deploy. A copy looks the same as a hand-made entry, so the installer never removes a copy. That is the price of copy over link.

## Managed block

A fenced region inside an owned dotfile, marked by `# >>> <tag> >>>` … `# <<< <tag> <<<`, that the dotfiles repo owns and rewrites freely. Everything outside the fence belongs to the user and is never touched. `utils/managed_block.sh::write_managed_block` is the pure transform that upserts a block; `install_managed_block` is the interactive wrapper that handles [[First-time placement]] into a pre-existing file. A block may declare a [[Block anchor]] to control where it lands on first-time placement.

## First-time placement

The case where an owned dotfile already exists but has no managed block for the given tag — i.e. the user has hand-rolled content that predates this install. `install_managed_block` prompts (backup / append / overwrite, default backup) only here. Subsequent runs (block present, file absent/empty, or file containing only other managed blocks) are quiet.

## Block anchor

An optional ordering constraint on a [[Managed block]] naming another block that must precede it in the same file. Expressed at the install site as the `--after <tag>` flag to `install_managed_block` (and `write_managed_block`). Consulted **only on [[First-time placement]]**; if the dependent block already exists in the file, the position is preserved and the anchor is not re-checked. On first-time placement, if the anchor tag is absent the install dies — the anchor expresses a precondition, not a fallback. Knowledge flows from dependent to anchor (the dependent block names the anchor's tag), which conventionally means framework → base (e.g. `dotfiles:zimfw` anchors on `dotfiles:zsh:base`). The anchor is *not* persisted in the fence; it lives only in the install-time call.

## Inlined vs sourced runtime config

Some runtime config lives in a repo file that the managed block *sources* (e.g. `zsh/zshrc-base`, `zimfw/zshrc-zim`). Some is *inlined* — written verbatim into the managed block by the install script (e.g. the XDG/ZDOTDIR exports owned by `install_zsh_zshenv`).

The split is by trait, not convention:

- **Inline** when the content is short, stable, and would otherwise create a lockstep between the sh-side install helpers and a zsh-side runtime file (the two layers must agree on default paths). Inlining makes the install script the single source of truth and saves one file source on every zsh startup. Cost: edits only take effect after re-running the wizard.
- **Source** when the content is substantial, has its own dev cycle (edit-and-reload), or defines functions/aliases users iterate on. The repo file can be edited live without re-running the installer.

## Deploy profile

The answers a `deploy.sh` run was given, recorded at `$(xdg_state_home)/dotfiles/profile` so a later run can replay them instead of asking again. **Answers, not outcomes**: a module the user said yes to stays in the profile even when its install failed, so the next run retries it rather than dropping it forever. State, not config — a record of what deploy was told, not a file to hand-edit; `deploy.sh` rewrites it at the end of every run that reaches the end, and a run that dies partway leaves the previous profile intact.

In memory the profile is `$DOTFILES_ANSWERS`, a space-separated `key=y|n` map that can also be set by hand for a canned run. The variable outranks the file: `deploy.sh` loads the profile only when `DOTFILES_ANSWERS` is *unset*, so a caller that sets it — even to empty — gets the run it asked for. An empty map is how a caller asks for a fresh interview. `lifecycle/deploy_profile.sh` owns both halves.

## Answer key

The name a prompt carries so a [[Deploy profile]] can address its answer by name rather than by position, passed as `confirm -k <key>`. Only prompts that are *deployment choices* get one — the module questions in `deploy.sh`. A prompt about the state of this machine right now ([[First-time placement]], a version clash, a backup choice) stays unkeyed and is always asked, because replaying it would answer a question about a file nobody has looked at yet.

A recorded answer short-circuits the prompt without reading stdin, and still prints the line as an answered prompt so a replayed run reads like one somebody sat through. An unrecorded key falls through to stdin, which is how a module added upstream after the profile was written gets asked about exactly once.

A key that no prompt claims is treated by where the map came from. In a map a *caller* supplied it is a typo and is fatal (`validate_answers`), because honouring the rest of it would produce a run quietly different from the one asked for. In a map read back from the *profile* it is drift — the repo renamed or dropped that module — so it is discarded with a warning (`drop_unknown_answers`) rather than stranding everyone who has a profile behind an upstream rename.

## XDG paths module

`utils/xdg_paths.sh` is the single repo-wide source for XDG Base Directory paths and tool-specific subdirs. It exposes path segments as constants (`XDG_CONFIG_DEFAULT_SUBPATH=.config`, `ZDOTDIR_SUBPATH=zsh`, etc.) AND the sh-side helpers that consume them (`xdg_config_home`, `get_zdotdir`, `get_zim_home`, `get_tmux_plugins_dir`).
