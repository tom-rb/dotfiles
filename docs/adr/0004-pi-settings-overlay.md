# Deep-merge a partial overlay into pi's `settings.json` via Node

Every other configurable tool in this repo writes into an [[Owned dotfile]] through a [[Managed block]] — a fenced region the repo rewrites wholesale while leaving the rest of the file to the user. `pi`'s config (`$(get_pi_config_dir)/settings.json`, default `~/.pi/agent/settings.json`) can't use that mechanism for two reasons: it's JSON, which carries no comment fence to mark a managed region; and `pi` itself rewrites the file at runtime (bumping `lastChangelogVersion`, appending extensions on `pi install`), so any fence we wrote would be clobbered or corrupted by the tool we're configuring.

The decision: model pi's config as a [[Settings overlay]] (see CONTEXT.md). The repo ships a **partial** `pi/settings.json` holding only the keys it wants to assert, and an install step deep-merges it *over* the live file with three rules — repo-shipped scalar keys win, scalar arrays merge by union (every repo element ensured present, live-only elements kept), and nothing is ever deleted. The merge writes to a temp file and `mv`s it into place (atomic, so a concurrent `pi` read never sees half-written JSON); there is no `.bkp`, because the never-delete property keeps the blast radius small and a backup-per-run would just accumulate. The overlay deliberately omits volatile keys (`lastChangelogVersion`) and the extensions array — extensions are pi-owned and materialized separately by `pi/install_pi_extensions.sh` running `pi install`, which records them into `settings.json` itself.

Why repo-wins-but-never-delete, and not the obvious alternatives:

- *Seed-only (fill absent keys, never overwrite).* Lets the user and pi's runtime always win, but then the repo can never push an updated default — re-running the wizard wouldn't correct a value the user drifted away from. We want the repo to be authoritative for the keys it ships.
- *Whole-file copy (overwrite settings.json).* Destroys pi's runtime keys and the user's own additions on every run. A non-starter for a file with multiple writers.
- *Wholesale-replace arrays (jq's `*` semantics).* Would drop models/entries the user or pi added to a repo-shipped array. Union honors "never delete"; the cost is that union only has clean identity for scalars, so the overlay must avoid shipping arrays-of-objects — an acceptable authoring constraint.

Why Node as the merge engine, in a repo that is otherwise pure POSIX `sh`:

- The merge needs a real JSON parser; `sh` has none, and hand-rolling one is out of the question.
- `jq` would mean a new package-manager dependency, and its built-in merge replaces arrays — union semantics need a hand-written ~10-line filter.
- `python3` expresses the merge cleanly but introduces a second general-purpose language and isn't default on every target image (e.g. amazonlinux-2).
- Node is **already guaranteed**: `ensure_node` provisions it as pi's own runtime (pi is a global npm package, `@earendil-works/pi-coding-agent`), so the merge engine rides on a dependency the module installs anyway. The merge lives in a committed `pi/merge_settings.mjs` rather than an inline `node -e` string so it can be unit-tested.

The load-bearing property is that the repo is *one of several writers* to this file, not its sole owner — the opposite of the managed-block contract. The overlay asserts only the keys it names and stays out of the way of everything else pi and the user put there.
