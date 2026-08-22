# Work tracker

Backend: **local markdown**. Container: `docs/work/`.

Every item of planned work is one markdown file under `docs/work/`. An effort's tasks live in a directory named after the effort's bare id, beside the effort's file:

```
docs/work/
  i001-zsh-and-tmux.md            ← an effort with no tasks
  f003-federated-search.md        ← an effort
  f003/                           ← its tasks, created lazily
    g001-product.md
    g002-architecture.md
    s003-tracer-bullet.md
    assets/
      m001-home-mockup.html       ← artifacts that cannot be a body
  w004-auth-strategy.md
  w004/
    t001-oauth-providers.md
    t001/
      assets/                     ← a task can own assets too
```

 - The **id** is the leading token of the filename, before the first dash: a type prefix plus a three-digit number — `f003`, `s003`. The **ref** is the id path from `docs/work/`: `f003/s003`. The **parent** is the directory. None of the three is stored in the file, so none of them can drift.
 - The number is unique **within its directory** and increases with creation, whatever the prefix. Sorting on it gives creation order. That is why the first slice above is `s003` and not `s001` — two gates were created before it.
 - The **prefix is the type**, and the only place the type is stored.
 - The **slug** is a hint for `ls`. It is set at creation and never renamed; the title is free to drift from it.
 - The **title** lives in frontmatter and nowhere else. The body has no `H1`.

## Types

| Type      | Role   | Prefix | Asked for by    |
|-----------|--------|--------|-----------------|
| `map`     | effort | `w`    | wayfinder       |
| `task`    | task   | `t`    | wayfinder       |
| `feature` | effort | `f`    | ways-of-working |
| `gate`    | task   | `g`    | ways-of-working |
| `slice`   | task   | `s`    | ways-of-working |
| `idea`    | effort | `i`    | parked by hand  |

List your own types only. An agent running wayfinder reads `w*` and `t*`; it never reads `f*`.

## States

| State    | Resolved | Meaning                                             |
|----------|----------|-----------------------------------------------------|
| `todo`   | no       | open and unclaimed                                  |
| `doing`  | no       | claimed — a session is working it                   |
| `closed` | yes      | carries `resolution: done` or `resolution: dropped` |

Reopening is one `update`: set `state: todo` and remove `resolution`.

Resolving is two operations, in this order: `add_note` what the outcome was, then `update` the state. The state says *that* it ended; the note says *how*, and the body is never rewritten to hold it.

## Claiming

 - **Claim** — `update` the item's `state` to `doing`, before any work on it.
 - **Release** — `update` it back to `todo`.
 - **Unclaimed** — the items whose `state` is `todo`.

A claim is advisory. Two sessions that read the file at the same moment both write `doing` and neither notices. Where the unclaimed list is empty and unresolved work remains, everything left is claimed or blocked — and a session that died leaves its item claimed forever, so name the stranded items to the user and break the claim with their agreement rather than reporting the effort as stuck.

## Labels

| Label                                                                               | On               | Set by          |
|-------------------------------------------------------------------------------------|------------------|-----------------|
| `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, `wayfinder:task` | a wayfinder task | wayfinder       |
| `gate:1` … `gate:4`                                                                 | a gate           | ways-of-working |

## An item file

```markdown
---
title: Tracer bullet — search returns a hardcoded hit
state: doing
labels: [gate:3]
blocked_by: [f003/g002]
---

<the body: prose, a document, a question — whatever the type carries>

## Notes

- 2026-08-22 — claimed and started against the stubbed handler.
```

`resolution` appears only once the state is `closed`. `labels` and `blocked_by` appear only when used.

State lives in the item's own frontmatter and nowhere else. Nothing caches it — no parent checklist, no status file — so a claim touches only the claimed item, and two sessions working different items never touch the same file.

## Verbs

 - `create(type, title, body, parent, labels)` — rescan the target directory for the highest number of **any** prefix, add one, write the file. **Rescan immediately before writing**; never reuse a number read earlier in the session, since other sessions create items concurrently. The rescan reads the numbers off the filenames rather than globbing them, so it also runs against a directory that is empty or does not exist yet — the lazily created tasks directory of a fresh effort. There it prints nothing, and the next number is `001`:
   ```sh
   find docs/work/f003 -maxdepth 1 -name '*.md' -printf '%f\n' 2>/dev/null | cut -c2-4 | sort -n | tail -1
   ```
   The same command reads the efforts themselves, pointed at `docs/work`.
 - `get(ref)` — `cat docs/work/f003/s003-*.md`
 - `list(filter)` — glob the candidate files, read their frontmatter, filter in the shell. Read **every** field you filter on in one pass. Bodies hold markdown, and a gate doc's body holds code blocks, so a plain `grep` for `^state:` matches inside them — stop at the second `---`:
   - every task of an effort:
     ```sh
     awk 'FNR==1{n=0} /^---$/{n++;next} n==1 && /^(title|state|resolution|labels|blocked_by):/{print FILENAME":"$0}' docs/work/f003/*.md
     ```
   - one type only: the same, globbed `docs/work/f003/s*.md`
   - efforts of one type: `docs/work/w*.md`
   - by label, anywhere — anchored, so `gate:1` does not match `gate:10`:
     ```sh
     awk 'FNR==1{n=0} /^---$/{n++;next} n==1 && /^labels:/ && /(\[|[[:space:]])gate:1([],]|$)/{print FILENAME}' docs/work/*/*.md
     ```
   - `FNR==1{n=0}` is what resets the counter per file. Without it every file after the first is read as body.
   - a conjunction is one read followed by filtering on the fields it returned, not a second pass.
   - creation order falls out of `sort`, because the three-digit number is fixed-width and leads the filename.
 - `update(ref, fields)` — edit the frontmatter in place. Nothing here moves a file, so no `update` changes a ref. A field is written whole, so appending to a `body` means reading it, adding the line, writing it back — use `add_note` where an append must not be lost.
 - `add_note(ref, text)` — append a dated entry to `## Notes`, newest last. Never rewrite an existing entry.
 - `attach(ref, name, content)` — write the file into the item's `assets/` directory, and link it from the body.

A body that mentions another item writes that item's ref verbatim: `f003/s003`.

## When an item is missing

A ref that does not resolve means the file is not there. Look for it by title before giving up — but one rule overrides everything else:

> Never create an item to recover from one you could not find. Stop and say what is missing.
