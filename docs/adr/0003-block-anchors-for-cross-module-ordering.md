# Use call-site block anchors to order cross-module `.zshrc` blocks

`.zshrc` is co-owned by `zsh/` and `zimfw/`: zsh writes a baseline configuration block and an overrides block (e.g. local-history keybindings, alias overrides) that should win on conflict; zimfw writes its own block in between. The required order is `dotfiles:zsh:base → dotfiles:zimfw → dotfiles:zsh:overrides`. The previous "one tag per module, position = install order" rule could not express this — zimfw appended after both zsh blocks.

The decision: introduce a [[Block anchor]] (see CONTEXT.md) — an optional ordering constraint passed as `--after <tag>` to `install_managed_block`, consulted only on [[First-time placement]]. zimfw's `.zshrc` block is installed with `--after dotfiles:zsh:base`. Re-installs are position-preserving: if the dependent block already exists in the file, the anchor is not re-checked and the block stays where it is. On first-time placement, if the anchor tag is absent the install dies (the anchor expresses a precondition, not a fallback). The anchor lives only in the install-time call — it is **not** persisted in the fence header.

Why this direction and not others:

- *Have zsh's overrides block declare `after: dotfiles:zimfw` instead.* Works on the second run but requires either re-running the zsh wizard after zimfw, or having `install_managed_block` re-check constraints across every block on every write. Both bleed complexity into the primitive or the user's invocation order. The inverted form (zimfw anchors on zsh) is correct on the first install and needs no cross-block state.
- *Let zimfw's installer reach into zsh's blocks directly.* Violates the self-contained [[Module]] invariant in CONTEXT.md. Rejected outright.
- *Move overrides into its own "personal" module installed last.* Architecturally the cleanest separation, but the whole repo *is* personal — promoting a `personal/` sibling alongside `zsh/`, `tmux/`, etc. would make the other modules read as if they weren't.
- *Let `deploy.sh` orchestrate the order by splitting zsh's wizard into `head` and `tail` steps interleaved around zimfw.* Pushes ordering knowledge into the orchestrator and breaks the "a module's wizard is a single composable unit" property that `wizard_main` / `start_module_wizard` rely on.
- *Persist the anchor in the fence header (`# >>> dotfiles:zimfw after=dotfiles:zsh:base >>>`).* Self-documenting at the rendered-file level, but anchors are consulted only on first-time placement — persisting them buys nothing at runtime, and it creates a second source of truth (on-disk fence vs. installer call) that can drift.

The asymmetry — only the framework declares the anchor, the base never names the framework — is the load-bearing property. It keeps knowledge flowing in the conventional direction (framework → base) and keeps the anchor mechanism a one-sided, no-state extension to `install_managed_block`.
