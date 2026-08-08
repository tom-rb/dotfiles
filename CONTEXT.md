# Domain Language

This file is the glossary for the dotfiles repo. When code or docs name a concept, they must use the term defined here. Add a new term before you use it, or at the same time you use it.

## Module

A per-tool slice of the repo, such as `git/`, `tmux/`, or `zsh/`. A module owns its configuration files, its install script, and its tests. A module is self-contained: it uses shared helpers from `utils/`, but it does not depend on any other module.

## Lifecycle directory

`lifecycle/` is not a module. It holds the code behind the repo's top-level entry points, such as `deploy.sh`, when no single module owns that code.

The difference between `lifecycle/` and `utils/` is about who uses the code. Every module can use code in `utils/`. Code in `lifecycle/` serves only the top-level entry points, so it stays out of `utils/` and out of any module's install script.

## Wizard

A wizard is the user-facing install flow for a module. It runs a list of [[Wizard step]]s in order, and it stops at the first step that fails. A wizard can run interactively, asking the user to confirm each step, or non-interactively, accepting the default answer for every step.

## Wizard step

One step in a wizard's chain, typically a program install, a dotfile render, or an action that runs after install. Each step takes no arguments. A module that needs to pass a value into a step wraps the call in its own no-argument function. The wizard stops at the first step that does not succeed.

## Wizard runner

The shared machinery that runs a wizard's step list and reports the outcome of each step. Every module's wizard uses the same runner, so wizards behave the same way across the repo. The runner also lets `deploy.sh` start a module's wizard from outside that module, without letting a failure in one module stop the others.

## Task

One line of terminal output for a unit of work. A task opens with a message that shows work is starting, and it closes with an [[Outcome]]. The caller that starts a task never closes it directly, the shared task helper does that. A [[Wizard step]] is usually made of several tasks.

## Outcome

How a [[Task]] ends: ok, skip, warn, or fail. The outcome comes from the exit status of the command the task ran, plus the wording the caller gave the task helper.

## Owned dotfile

A configuration file in the user's home directory, or in a directory such as `$ZDOTDIR` or `$XDG_CONFIG_HOME`, that the user owns but the dotfiles repo wants to write into. The user may already have their own content in that file, from before they installed the dotfiles. Overwriting it without asking would be hostile to the user.

## Owned entry

One item a [[Module]] installs into a directory it shares with the user, such as a skill directory or a rule file. The repo proves it owns an entry by checking that the entry is a symlink pointing back into the repo. A copy of that same content looks identical to something the user made by hand, so the repo cannot tell the two apart. When the repo stops shipping an entry, it removes only the entries it can prove it owns. A symlink the repo made is removed cleanly, but a copy, or a link the user made themselves, is left alone. That is the cost of choosing copy over link.

## Managed block

A marked region inside an [[Owned dotfile]] that the dotfiles repo owns and rewrites freely. Everything outside the marked region belongs to the user and is never touched. On [[First-time placement]], a block can name another block as its [[Block anchor]] to control where it lands in the file.

## First-time placement

The case where an owned dotfile already exists but has no managed block for the tag being installed, meaning the user has hand-made content that predates the install. Here, and only here, the installer asks the user how to proceed: back up the existing file, append to it, or overwrite it. The default is backup. Every later run stays quiet, because the block already exists, or the file is empty or missing, or the file holds only other managed blocks.

## Block anchor

An optional rule on a [[Managed block]] that says another block must already exist earlier in the same file. The install step for the dependent block names its anchor. This rule applies only on [[First-time placement]]: if the block already exists in the file, its position stays as is, and the anchor is not checked again. If the anchor is missing on first placement, the install fails, because the anchor states a requirement, not a fallback. The anchor itself is not written into the file, it exists only at install time.

## Inlined vs sourced runtime config

Some runtime config lives in a repo file that the managed block loads by reference. Other runtime config is inlined: written directly into the managed block by the install script.

The choice depends on the nature of the content, not on convention.
- Inline it when the content is short and stable, and keeping it in the install script avoids two files needing to agree on the same defaults. The cost: a change only takes effect after the user reruns the wizard.
- Keep it in a separate file when the content is larger, changes often, or defines something the user edits directly, such as functions or aliases. The user can then edit that file and see the change right away, without reinstalling.

## Deploy profile

The record of the answers a `deploy.sh` run was given, saved so a later run can replay them instead of asking again. The profile stores answers, not outcomes: if the user says yes to a module but its install fails, the profile still remembers yes, so the next run tries that module again instead of skipping it forever. The profile is state, not configuration, and it is not meant to be hand-edited. `deploy.sh` rewrites it at the end of every run that completes, and a run that dies partway through leaves the previous profile untouched.

A caller can also supply answers directly, bypassing the saved profile entirely. This is how a caller asks for a fresh run, or replays a canned set of answers, without touching the file on disk.

## Answer key

The name a prompt carries so a [[Deploy profile]] can store and recall its answer by name. Only prompts that represent a deployment choice, such as whether to install a given module, get a key. A prompt about the current state of the machine, such as [[First-time placement]] or a version conflict, is never keyed. It always asks, because replaying a stored answer would answer a question about a file nobody has actually looked at.

A stored answer skips the prompt without reading input, but still shows the line as answered, so a replayed run reads the same way a live one would. A prompt with no stored answer falls through to asking the user normally.

An answer with no matching prompt is handled differently depending on where it came from. If a caller supplied it directly, the run treats it as a mistake and stops. If it came from a saved profile, the run drops it with a warning instead, since the repo itself may have renamed or removed that prompt.

## XDG paths module

`utils/xdg_paths.sh` is the single place in the repo that defines XDG Base Directory paths and tool-specific subdirectories, both as path values and as the helper functions that build full paths from them.
