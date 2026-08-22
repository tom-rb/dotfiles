---
name: ways-of-working
description: The 4-gate feature workflow — Product, Architecture, Program Design, Vertical Slices — with explicit user approval at every gate before implementation code exists. Use when starting a new feature, a new project, or any task expected to change several files or produce a large diff. Not for trivial tweaks like renames, copy changes, or one-line config edits.
metadata: thanks to Dex Horthy
---

# Ways of Working in the Software Factory

Make every important decision before implementation code exists, where changing it costs a sentence instead of a rewrite. Work through four gates in order. Stop at each gate for explicit user approval. Never merge gates. Never write implementation code before the Gate 4 slice plan is approved.

## When to run the gates

Run the full workflow when the task is a real feature: it will create or change multiple files, add an endpoint, table, or screen, or produce a diff the user would hate to review all at once (roughly 100+ lines).

Skip the gates entirely (just do the task) when any of these hold:

 - Trivial tweak: rename, typo, copy change, style tweak, small config edit.
 - The user explicitly says to skip the process ("just vibe it," "quick and dirty," "no process").
 - The user says the code is throwaway or pure prototyping.

If unsure whether the task qualifies, ask once: "This looks big enough for the 4-gate workflow — run it, or do you want the fast version?" Respect the answer.

## The tracker

Everything this workflow produces is a work item. A **feature** is an `effort`. Each **gate doc** and each **slice** is a `task` under it, gates carrying a `gate:1` through `gate:4` label. A gate is the one task that isn't executed: its body *is* the deliverable, and the user's approval *is* its resolution. Each of the three takes a type name of its own, so that listing features never returns another skill's efforts — the tracker file's type table names the skill that asks for each type, and the rows naming **ways-of-working** are the ones to filter on. Mockups and other artifacts that can't be a body are `attach`ed to the item they belong to.

How this project's tracker names those, what its states are, how to claim an item, and how to invoke each verb are described in `docs/agents/work-tracker.md` — read it before the first operation. If that file is missing, this project has no tracker yet: stop and ask the user to run `/setup-my-skills`.

There is **no status file**. The feature's status is its tasks: `list` them and you have every gate's approval and every slice's progress, first-hand. Never mirror that onto the feature's body or anywhere else — a second copy is a copy that goes stale, and two sessions writing it collide.

## Starting and resuming

`create` the feature before Gate 1, titled with the feature's name. Its body is two or three sentences: what is being built and for whom. That's all — the gates hold the thinking, and the feature is what they hang off. Confirm you're working on a feature branch or ask the user if it's fine to proceed in the trunk. Anything decided in chat that a fresh session must know, and that isn't in code, in its comments, or in a gate doc, goes on the feature with `add_note`.

**Resume rule:** at the start of any session, find out whether a feature already exists for what's being discussed — `list` the unresolved features and read their titles. The tracker has no text search, so this is a read and a judgement, not a query. If one matches, confirm with the user that it's the same feature before touching it.

Then `get` it, `list` its tasks, and `get` every resolved gate doc. Continue from the first unresolved gate, or the first unresolved slice. Never redo an approved gate unless the user asks for it or a later gate invalidated it.

Commit the work right after every gate approval and every slice completion.

## The approval protocol (run at every gate)

1. `create` the gate doc as a `task` under the feature, titled `<gate name>: <feature name>`, carrying the gate's label, with its body written in full. The title carries the name, so the body starts at the first section — no heading above it.
2. Present a summary to the user: at most 5–8 bullet decisions, plus the item's ref. Do not paste the whole doc into chat.
3. Ask exactly: **"Approve Gate N, or what should change?"**
4. Approval means the user clearly says yes / approve / continue. Anything else means: `update` the body to address their answer, then re-ask.
5. On approval, `update` the gate doc to a resolved state and move on.
6. **Backtracking:** if work at a later gate reveals an earlier approved decision is wrong, stop, `update` that gate doc, **reopen** it — a non-resolved state, `resolution` cleared — and get re-approval before continuing.

## Gate 1 — Product (no tech talk)

Work with the user to fill this template as the gate doc's body:

```markdown
## Problem
<the user problem, in the end-user's words — not the developer's>

## Success metric
<one real number tied to the business (conversion, latency, tickets, revenue) and how it's measured>

## Announcement — the blog post before the feature
<3–6 sentences announcing this feature to users. If you can't write it, you're building the wrong thing.>

## Screens
<one line per mockup attached to this gate doc — or "no UI">
```

Rules for this gate:

 - **Banned in this stage:** databases, schemas, endpoints, architecture, file names. If tech appears, move it to Gate 2.
 - For anything with a UI: produce one plain HTML file per screen — no framework, no build step, throwaway by design — and `attach` each to this gate doc. Iterate on the mockups with the user until they say "yes, that".

Run the approval protocol.

## Gate 2 — Architecture

Read the relevant existing code before writing this doc — never design against an imagined codebase.

```markdown
## Fit
<which existing services/modules this touches, and how>

## Endpoints/API
<if http-like application: route + verb + purpose, one line each — or "none">
<if local ui↔core application: core entrypoint + purpose, one line each — or "none">

## Data
<new or changed tables/collections, with outlines of the queries that will hit them>

## Flow
<the end-to-end call order for the main path: what calls what>

## External
<third-party APIs, env var NAMES (never values), webhooks — or "none">
```

Run the approval protocol.

## Gate 3 — Program Design (the step everyone skips)

The decisions the agent would otherwise make silently mid-implementation.

```markdown
## Files
<every file created or changed, one line each on why it lives there>

## Types & signatures
<code blocks defining the types and method signatures — NO implementation bodies.
A human should be able to read these in seconds and say "right" or "wrong.">

## Call stack
<for each main flow: what calls what, top to bottom>

## Test plan
<test case names and what each one asserts — before any of them exist>

## Least confident decisions
<numbered list of the calls most worth challenging now, while changing them is free>
```

Run the approval protocol.

## Gate 4 — Vertical Slices (tracer bullets)

The Gate 4 gate doc's body is the **slice plan**: one line per slice, in build order. Run the approval protocol on it. Only then `create` the slices under the feature — **in plan order, one after the other** — and build one at a time.

Creation order is the build order, because `list` returns it. So the next slice to build is the first unresolved slice `list` gives back, and no cross-referencing between the plan and the slices is needed.

Slice rules:

 - **Slice 1 is the tracer bullet:** a mocked/hardcoded endpoint and a stubbed UI (or curl-able response), wired end to end. It does almost nothing — but it runs, and the user can see it.
 - **Slice 2:** replace mocks with the real logic for the single happy path.
 - **Slice 3+:** one capability per slice — a business rule, error handling, an edge case, polish — each ending in a working, testable state.
 - **Banned:** horizontal building (all of the database, then all services, then all API, then all frontend, with nothing testable until the end).

Claim a slice before you touch code, so a concurrent session skips it — the tracker file says how. A claim is advisory and will not stop a second session claiming the same slice, so where the user is running sessions in parallel, say plainly that two sessions can land on one slice.

After **every** slice:

1. Prove it works — run it, curl it, or browser-test it, and show the user the result.
2. `update` the slice to a resolved state.
3. Ask: "Continue to slice N+1, or re-steer?" If the trajectory is wrong, fix direction before adding more code.

When the last slice in the plan resolves, the feature is built: `add_note` what shipped and `update` the feature to a resolved state. Resolving every task does not resolve the feature, so an unfinished-looking feature list is what you get if you skip this.

## Standing rules (always on during the workflow)

 - **Compact at every boundary.** At the end of every gate and every slice, make sure the tracker holds everything decided — nothing _important_ may exist only in chat. What belongs to a gate goes in its body; anything else goes on the feature with `add_note`. Tell the user this is a safe point to start a fresh session; a new session must be able to continue from the tracker alone (see the resume rule).
 - **Keep diffs reviewable.** Small slices. If the user hasn't looked at code in a long stretch, nudge them at a slice boundary — losing touch with the codebase costs weeks, exactly when the agent hits a bug it can't solve.
 - **Real tests only.** Never write a test that passes against the pre-change code — a test that can't fail tests nothing. Never comment out, skip, or weaken a test to get to green.

## Optional: durable context in the codebase

A gate doc is a work item because it is waiting on an approval. What outlives the feature is documentation, and it lives in the codebase, not the tracker.

When a gate produces a decision that outlives this feature, offer to record it as an ADR in `docs/adr/` — context, decision, consequences; never rewrite old ADRs, supersede them. Record anything that lives outside the repo but that an agent needs to know exists (env var names, payment setup, test accounts, third-party dashboards) in `docs/external/`. Files on disk are free context — every future session starts smarter.
