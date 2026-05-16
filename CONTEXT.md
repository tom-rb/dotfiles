# Domain Language

This file is the glossary for the dotfiles repo. When code or docs name a concept, it should use the term defined here. New terms get added before (or as) they're used.

## Module

A per-tool slice of the repo — `git/`, `tmux/`, `zsh/`, `zimfw/`, plus shared infrastructure under `utils/`. A module owns its configuration files, its install script, and its tests. Modules are self-contained: they source `utils/utils.sh` for shared helpers and otherwise know nothing about each other.

## Wizard

The user-facing install flow for a module, exposed as `install_<module>_wizard` and triggered by `sh <module>/install_<module>.sh --wizard`. A wizard composes the smaller install steps (program, dotfiles, post-install) into an `&&`-chain, and accepts `-y` to accept default answers for every interactive prompt.

## Owned dotfile

A configuration file in the user's home (or `$ZDOTDIR`, `$XDG_CONFIG_HOME`, etc.) that the user owns but the dotfiles repo wants to write into. The user may have hand-rolled content there from before they installed the dotfiles — overwriting it blindly is hostile.

## Managed block

A fenced region inside an owned dotfile, marked by `# >>> <tag> >>>` … `# <<< <tag> <<<`, that the dotfiles repo owns and rewrites freely. Everything outside the fence belongs to the user and is never touched. `utils/managed_block.sh::write_managed_block` is the pure transform that upserts a block; `install_managed_block` is the interactive wrapper that handles first-time placement into a pre-existing file.

## First-time placement

The case where an owned dotfile already exists but has no managed block for the given tag — i.e. the user has hand-rolled content that predates this install. `install_managed_block` prompts (backup / append / overwrite, default backup) only here. Subsequent runs (block present, or file absent) are quiet.
