# Backend — local markdown

The **bindings** for the local markdown tracker: the state list, the claim recipes, the label set, and the six verbs.

## The layout

Use the layout below. It is the recommended design; settle only the type names and their id prefixes with the user.

Every item is one markdown file under `docs/work/`. An effort's tasks live in a directory named after the effort's bare id, beside the effort's file:

```
docs/work/
  e001-<effort-slug>.md              ← an effort with no tasks yet
  e002-<effort-slug>.md              ← an effort
  e002/                              ← its tasks, created lazily
    p001-<task-slug>.md              ← a task of one type
    p002-<task-slug>.md
    q003-<task-slug>.md              ← a task of a second type, same counter
    q004-<task-slug>.md
    assets/
      m001-<asset-slug>.html         ← artifacts that cannot be a body
  e003-<effort-slug>.md
  e003/
    p001-<task-slug>.md
    p001/
      assets/                        ← a task can own assets too
```

These rules make the layout work:

 - The **id** is the leading token of the filename, before the first dash: a type prefix plus a **three-digit number**, `e002`, `q003`. The **ref** is the id path from the container root: `e002/q003`. The **parent** is the directory. None of the three is stored in the file — the path already says them, so they cannot drift, and reparenting is a `git mv`.
 - The number is unique **within its directory** and increases with creation, whatever the prefix. That is what makes `list` return creation order: sort on the number, ignore the prefix. It is why the first `q` task above is `q003` and not `q001` — two `p` tasks were created before it.
 - **The prefix is the `type`.** It is the only place the type is stored, so `list(type=...)` is a glob: `docs/work/e002/q*.md`. Frontmatter never repeats it.
 - The **slug** in a filename is a hint for `ls`. It is set at creation and never renamed; the title is free to change and drift from it. The tasks directory carries the bare id with no slug, so it never needs touching.
 - The **title** lives in frontmatter and nowhere else. The body has no `H1`.

An item file:

```markdown
---
title: Tracer bullet — search returns a hardcoded hit
state: doing
labels: [area:search]
blocked_by: [e002/p001]
---

<the body: prose, a document, a question — whatever the type carries>

## Notes

- 2026-08-21 — claimed and started against the stubbed handler.
```

`resolution` appears only once the state is resolved. `blocked_by` appears only when used.

## States and claiming

The states are `todo`, `doing`, and `closed`, and `closed` is the resolved one, carrying a `resolution` of `done` or `dropped`. This mirrors the shape GitHub enforces, so a skill author reasoning about one backend is reasoning about both.

The claim is a **state** here: `doing` is the in-progress state and `todo` is what a release puts the item back to. Claim by `update`-ing to `doing`, release by `update`-ing to `todo`, and list unclaimed work by filtering `state` to `todo`. Even here the claim is advisory: two sessions that read the file at the same moment both write `doing` and neither notices.

State lives in the item's own frontmatter and nowhere else. Nothing caches it — no parent checklist, no status file — so a claim touches only the claimed item, and two sessions working different items never touch the same file.

## Labels

Labels go in the `labels` frontmatter list. Nothing here provisions them, so the declared set needs no setup work — but the set is still closed: a `create` uses a declared label and never invents one.

Nothing about this backend needs a label to store a field, so the label set is exactly the one in `types-and-labels-registry.md`.

## The verbs

 - `create` — rescan the target directory for the highest number of **any** prefix, add one, write the file. **Rescan immediately before writing**; never reuse a number read earlier in the session, since other sessions create items concurrently. The rescan reads the numbers off the filenames rather than globbing them, so it also runs against a directory that is empty or does not exist yet — the lazily created tasks directory of a fresh effort. There it prints nothing, and the next number is `001`:
   ```sh
   find docs/work/e002 -maxdepth 1 -name '*.md' -printf '%f\n' 2>/dev/null | cut -c2-4 | sort -n | tail -1
   ```
   The same command reads the efforts themselves, pointed at `docs/work`.
 - `get` — `cat docs/work/e002/q003-*.md`
 - `list` — glob the candidate files, read their frontmatter, filter in the shell. Read **every** field a caller filters on, not just the ones a given call needs — `labels` and `blocked_by` are what a caller computing blocked work needs, and a recipe that omits them cannot answer. Bodies hold markdown, and a body that holds a code block can hold a line reading `state:` at column 0, so a plain `grep` matches inside it. Stop at the second `---`:
   - every task of an effort:
     ```sh
     awk 'FNR==1{n=0} /^---$/{n++;next} n==1 && /^(title|state|resolution|labels|blocked_by):/{print FILENAME":"$0}' docs/work/e002/*.md
     ```
   - one type only: the same, globbed `docs/work/e002/q*.md`
   - efforts of one type: `docs/work/e*.md`
   - by label, anywhere — anchored, so `area:search` does not match `area:searchx`:
     ```sh
     awk 'FNR==1{n=0} /^---$/{n++;next} n==1 && /^labels:/ && /(\[|[[:space:]])area:search([],]|$)/{print FILENAME}' docs/work/*/*.md
     ```
   - `FNR==1{n=0}` is what resets the counter per file. Without it every file after the first is read as body.
   - a conjunction — the common case — is one read of the tasks followed by filtering on the fields it returned, not a second pass.
   - creation order falls out of `sort`, because the three-digit number is fixed-width and leads the filename.
 - `update` — edit the frontmatter in place. Nothing here moves a file, so no `update` changes a ref.
 - `add_note` — append a dated entry to `## Notes`, newest last. Never rewrite an existing entry.
 - `attach` — write the file into the item's `assets/` directory, and link it from the body.

## Verify

Only with the user's agreement, round-trip one throwaway item: create it, read it back, resolve it. The tracker has no delete verb, so clear the throwaway away by hand afterwards.

Nothing before this point wrote to the repository, so there is nothing else to undo.

## What the rendered file has to carry

Beyond the generic list at the end of `work-tracker-vocabulary.md`, the rendered `docs/agents/work-tracker.md` needs four things from this file, because a working agent cannot write a single item without them:

 - **The layout sketch**, and the rules that go with it: how an id, a ref, and a parent are read off a path, that the number is unique per directory across all prefixes, and that the prefix is the type. An agent that has to invent a filename gets these wrong.
 - **The frontmatter shape of an item file**, as a fenced example.
 - **The `create` rescan**, verbatim, so the first item created in a fresh directory gets a number instead of an error.
 - **The awk recipes**, verbatim, with the project's own type prefixes substituted in. The `FNR==1{n=0}` reset and the second-`---` bound are the parts that get dropped when someone retypes them from memory, and both fail silently.
