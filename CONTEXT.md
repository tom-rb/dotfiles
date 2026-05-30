# Domain Language

This file is the glossary for the dotfiles repo. When code or docs name a concept, it should use the term defined here. New terms get added before (or as) they're used.

## Module

A per-tool slice of the repo — `git/`, `tmux/`, `zsh/`, `zimfw/`, `asdf/`, plus shared infrastructure under `utils/`. A module owns its configuration files, its install script, and its tests. Modules are self-contained: they source `utils/utils.sh` for shared helpers and otherwise know nothing about each other.

## Wizard

The user-facing install flow for a module, exposed as `install_<module>_wizard` and triggered by `sh <module>/install_<module>.sh --wizard`. A wizard is a list of [[Wizard step]]s composed by the [[Wizard runner]] into an `&&`-chain, with `-y` accepting default answers for every interactive prompt. The per-module `install_<module>_wizard` function is the adapter: it names the step list, the runner does everything else.

## Wizard step

One function in a wizard's chain — typically a program install, a dotfile render, or a post-install hook (e.g. `install_zsh_program`, `install_zsh_dotfiles`, `set_zsh_as_default_shell`). Steps are no-arg by convention; modules that need to parameterize a step (e.g. `install_tmux_program "$desired_version"`) wrap the call in a no-arg step function. The runner short-circuits on the first step that returns non-zero.

## Wizard runner

`utils/wizard.sh` — the shared machinery behind every wizard. Exposes two helpers: `wizard_run` (executes a step list, handles `-y` by piping `yes` into the chain) and `wizard_main` (the `--wizard` dispatch at the bottom of each installer script). Cross-module orchestration in `deploy.sh` uses `start_module_wizard <name>`, which shells out to the module's install script under a fresh `sh -- ` so a `die` in one module doesn't terminate the surrounding `deploy_wizard`.

## Owned dotfile

A configuration file in the user's home (or `$ZDOTDIR`, `$XDG_CONFIG_HOME`, etc.) that the user owns but the dotfiles repo wants to write into. The user may have hand-rolled content there from before they installed the dotfiles — overwriting it blindly is hostile.

## Managed block

A fenced region inside an owned dotfile, marked by `# >>> <tag> >>>` … `# <<< <tag> <<<`, that the dotfiles repo owns and rewrites freely. Everything outside the fence belongs to the user and is never touched. `utils/managed_block.sh::write_managed_block` is the pure transform that upserts a block; `install_managed_block` is the interactive wrapper that handles [[First-time placement]] into a pre-existing file. A block may declare a [[Block anchor]] to control where it lands on first-time placement.

## First-time placement

The case where an owned dotfile already exists but has no managed block for the given tag — i.e. the user has hand-rolled content that predates this install. `install_managed_block` prompts (backup / append / overwrite, default backup) only here. Subsequent runs (block present, file absent/empty, or file containing only other managed blocks) are quiet.

## Block anchor

An optional ordering constraint on a [[Managed block]] naming another block that must precede it in the same file. Expressed at the install site as the `--after <tag>` flag to `install_managed_block` (and `write_managed_block`). Consulted **only on [[First-time placement]]**; if the dependent block already exists in the file, the position is preserved and the anchor is not re-checked. On first-time placement, if the anchor tag is absent the install dies — the anchor expresses a precondition, not a fallback. Knowledge flows from dependent to anchor (the dependent block names the anchor's tag), which conventionally means framework → base (e.g. `dotfiles:zimfw` anchors on `dotfiles:zsh:base`). The anchor is *not* persisted in the fence; it lives only in the install-time call.

## Settings overlay

The mechanism for writing into an [[Owned dotfile]] that is a structured JSON document the owning tool *also rewrites at runtime* (e.g. `pi`'s `~/.pi/agent/settings.json`, which the agent mutates as it operates). Where a [[Managed block]] fences a region of a text file, a settings overlay can't — JSON carries no fence, and the tool's own writes would corrupt one. Instead the repo ships a **partial** settings document (only the keys it cares about) and deep-merges it *over* the live file: on every object, repo-shipped scalar keys win; keys the repo never names (the tool's runtime keys, the user's own additions) are left untouched; nothing is ever deleted. Arrays merge by union — every element the repo ships is ensured present, live-only elements are kept — so the overlay should ship only arrays of scalars, where union has a clean identity. Contrast [[Managed block]]: there the repo is the sole authority inside the fence and rewrites it wholesale; here the repo is one of several writers and only asserts the keys it owns.

## Inlined vs sourced runtime config

Some runtime config lives in a repo file that the managed block *sources* (e.g. `zsh/zshrc-base`, `zimfw/zshrc-zim`). Some is *inlined* — written verbatim into the managed block by the install script (e.g. the XDG/ZDOTDIR exports owned by `install_zsh_zshenv`).

The split is by trait, not convention:

- **Inline** when the content is short, stable, and would otherwise create a lockstep between the sh-side install helpers and a zsh-side runtime file (the two layers must agree on default paths). Inlining makes the install script the single source of truth and saves one file source on every zsh startup. Cost: edits only take effect after re-running the wizard.
- **Source** when the content is substantial, has its own dev cycle (edit-and-reload), or defines functions/aliases users iterate on. The repo file can be edited live without re-running the installer.

## XDG paths module

`utils/xdg_paths.sh` is the single repo-wide source for XDG Base Directory paths and tool-specific subdirs. It exposes path segments as constants (`XDG_CONFIG_DEFAULT_SUBPATH=.config`, `ZDOTDIR_SUBPATH=zsh`, etc.) AND the sh-side helpers that consume them (`xdg_config_home`, `get_zdotdir`, `get_zim_home`, `get_tmux_plugins_dir`).
