# Work tracker vocabulary

The generic system every skill in this repo assumes when it registers, reads, or advances planned work. It is written for the setup interview: read it to learn the system, then render a concrete instance of it into the project's `docs/agents/work-tracker.md`.

Working agents never read this file. They read the rendered instance, which names one backend, one container, and one set of type and state names.

Two backends are supported: a local tracker of markdown files, and GitHub Issues on a repository under a personal account. Everything below works on both. **There are no optional parts** — a backend that cannot do one of these things is not a supported backend, so no skill ever carries a fallback for a missing capability.

## Terms

 - **Work item** — one registered unit of planned work. The only entity. Short form in prose: *item*.
 - **Tracker** — the system that stores work items for a project.
 - **Container** — the single collection the tracker binds to: a directory, a GitHub repository. One project instance binds to exactly one container.
 - **Type** — the name a project gives to a kind of item. Every type is either an effort or a task.

## Efforts and tasks

An **effort** is a body of work that contains other work — the thing a skill charts, plans, or delivers over many sessions. It has no parent, and it may have no tasks at all.

A **task** is a unit of work with its own lifecycle, belonging to exactly one effort.

The tree is exactly these two levels. A lifecycle is the item's own: resolving an effort does not resolve its tasks, and resolving every task does not resolve the effort. Because each task carries its own state, the tasks of an effort *are* its status — no roll-up file, and nothing to keep in sync.

Skills share these two roles, so a role alone cannot tell one skill's work from another's. Each skill declares a **type name** of its own instead, and `list(type=...)` is what lets each see its own work and no one else's. A type is set at creation and never changes.

## Fields

| Field         | Value                       | Notes                                                                                                                            |
|---------------|-----------------------------|----------------------------------------------------------------------------------------------------------------------------------|
| `ref`         | opaque string               | How the item is written inside prose, in the backend's own notation. Minted by the tracker; read from a result, never assembled. |
| `title`       | one line                    | The item's **name**. Used whenever a human reads about the item.                                                                 |
| `body`        | markdown                    | Can be a full document.                                                                                                          |
| `type`        | one value                   | From the project's declared type list.                                                                                           |
| `state`       | one value                   | From the project's declared state list.                                                                                          |
| `resolution`  | `done`, `dropped`, or empty | Only on a resolved state.                                                                                                        |
| `parent`      | one `ref`                   | The effort a task belongs to. Empty on an effort.                                                                                |
| `blocked_by`  | set of refs                 | A task is unblocked when every task blocking it is resolved.                                                                     |
| `labels`      | set of strings              | Unordered, from the project's declared set. Any item may have none.                                                              |
| `notes`       | append-only entries         | Progress recorded without rewriting the body.                                                                                    |
| `attachments` | named files                 | Artifacts that cannot be a body: images, HTML mockups, raw data.                                                                 |

Nothing else is a field. Priority and rank are labels if a project wants them. A checklist is markdown inside the body; anything on it that deserves its own state is a task instead.

## States

Each backend has a fixed state list, which the rendered file names. Every state carries one flag: whether it is **resolved**. Generic skills branch on that flag; a project-aware skill may name a specific state.

A resolved state also carries a **resolution**, which distinguishes finished (`done`) from abandoned (`dropped`).

Reopening is an ordinary `update`: set a non-resolved state and clear the `resolution`.

State is orthogonal to labels.

## Claiming

An item is **claimed** while a session works it. Claiming is how concurrent sessions stay off each other's work, so the marker has to be visible to `list`. Every project has one. The rendered file gives three recipes: **claim** an item, **release** it, and `list` the **unclaimed** ones — the negation is what a skill picking up work actually asks for.

A claim is **advisory**. It says an item is being worked; it does not reserve it. Neither backend offers an atomic test-and-set, so two sessions can claim the same item and both proceed. Where that must not happen, the user sequences the sessions — the tracker will not.

Resolving an item releases its claim, because every skill reads claims across unresolved work only. A session that gives up on an item releases the claim by hand. A session that dies cannot, and strands the item unresolved and claimed, invisible to every skill that reads unclaimed work. Where the unclaimed list is empty and unresolved work remains, that is the signature: say so to the user, and break the stale claim with their agreement.

## Labels

Flat, unordered strings. A label a skill filters on uses the `key:value` form — `area:product`, `risk:high`. Skills treat labels as opaque and never assume one is present.

A field is never a label to a skill. Where a backend has no native home for one, the rendered file answers it with a label recipe — the skill still asks for the field, and never invents a label to carry one.

## Verbs

Six, and no more:

 - `create(type, title, body, parent, labels)` → returns the new item, with its `ref`. Only `type` and `title` are required. Every other field is an `update` afterwards.
 - `get(ref)` → one item
 - `update(ref, fields)` → partial, last write wins. Writing `state` leaves `body` alone. But a field is written whole, so appending a line to a `body` means `get` it, add the line, write it back — and a concurrent session doing the same loses one of the two lines. Where an append must not be lost, use `add_note`, which appends without a read.
 - `list(filter)` → items in **creation order**
 - `add_note(ref, text)`
 - `attach(ref, name, content)`

A **filter** is a conjunction of exact matches over `type`, `state`, resolved, `parent`, plus label membership. An exact match may test that a field is **empty** — that is how unclaimed work is asked for. No OR, no ranges, no text search, no sorting beyond creation order. A skill that needs more fetches and filters on its own.

There is no delete and no close. Abandoning an item is `update` to a resolved state with resolution `dropped`; finishing it is `update` to a resolved state. One mutation path for state, and no destructive verb.

Resolving an item is two operations, always in this order: `add_note` recording what the answer or outcome was, then `update` to the resolved state. The state says *that* it ended; the note says *how*, and the body is never rewritten to hold it.

## References inside prose

A body that mentions another item writes that item's `ref` verbatim, exactly as the result gave it: `#412`, `e002/q003`. This keeps every body native to its own tracker, where refs link themselves.

## Failure

Three outcomes are worth naming to a working agent, in a sentence or two each: the ref does not exist, the write was rejected, the operation is not available. One rule matters more than the rest and belongs in every rendered file:

> Never create an item to recover from one you could not find. Stop and say what is missing.

## Rendering the instance

The rendered `docs/agents/work-tracker.md` describes one tracker in the concrete. It states the backend and the container, the type table — one row per type name, giving whether it is an effort or a task and the skill that asks for it, because skills share the roles and each needs to list only its own — the state list with its resolved flag, how to claim an item and how to list the unclaimed ones, the labels the installed skills use, how to invoke each of the six verbs, and the failure rule above.

It carries no theory beyond the type table itself, and no mention of the backend the project does not use. Keep it short: working agents read this file on every planning task, so every line competes with the skill they are actually running.
