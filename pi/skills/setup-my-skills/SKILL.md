---
name: setup-my-skills
description: Set up a repository so the skills in this collection can work in it. Run once per repository, by the user.
disable-model-invocation: true
---

# Set up my skills

Prepare one repository for this skill collection. The user runs this once. Afterwards no agent reads this skill again — it leaves behind the files that working agents read instead.

Work through the steps below in order, with the user present.

---

## Step 1 — Instantiate the work tracker

Every planning skill here registers its work on a **work tracker**. This step decides which tracker the project uses and writes `docs/agents/work-tracker.md`, the concrete instance that working agents read. The step ends when that file is written.

Read `work-tracker-vocabulary.md`, next to this file, before starting. It defines the generic system. The interview below turns it into one concrete tracker, using the types and labels declared in `types-and-labels-registry.md`.

### Read what is already there

Look in `docs/agents/` for a tracker file — `work-tracker.md`, or something named for the same job like `issue-tracker.md`. If one is there, read it first and say so. It is load-bearing for the skills already in use, so never overwrite it silently. Offer to review and rewrite it, and pre-fill every answer below from what it already says. Treat the interview as a migration: what it currently tracks has to keep working under the new names.

### Choose the backend

There are two: the **local markdown** tracker, and **GitHub Issues** on a repository under a personal account.

Look for signals before asking. A GitHub remote plus an authenticated `gh` suggests GitHub Issues; existing planning files under `docs/` suggest the local tracker. Propose what you found, and **always offer the other as an alternative** — a repo with a GitHub remote is not automatically a repo whose planning belongs on GitHub. Let the user choose.

Each backend has its own file under `backends/`, holding every recipe for it. This choice picks which one is read; the rest of this step reads exactly one.

### Fill in the instance

One question, then one thing to confirm.

**Ask the container** — which directory or repository the tracker binds to. Exactly one.

**Propose the types and labels.** Both are declared in `types-and-labels-registry.md`, next to this file. Show them for confirmation rather than asking the user to invent names; they may rename any of them, and may add types of their own for work they park by hand. Every type name belongs to exactly one skill, so that `list(type=...)` returns that skill's work and no other's — carry the asking skill into the rendered table, because a table that gives only the role leaves an agent unable to tell which row is its own.

Check that file against the skills actually installed — they are the sibling directories of this one. A skill with no row has nowhere to put its work, and its `list` will return nothing rather than fail — so stop and say so rather than inventing a name for it.

Nothing else is a question. Everything that remains is the backend's **bindings**, which the next step writes.

### Write the bindings

The **bindings** are what makes the generic system concrete for one backend: the state list, the claim recipes, the label set, and the command for each of the six verbs.

They live in `backends/`, next to this file — one file per backend. Read **only** the one the user chose: the other describes a different tracker, and nothing in it carries over.

The **label set** is closed once written. It is the set from `types-and-labels-registry.md`, plus whatever the backend needs to store a field it has no native home for — the backend's file says which, and says none where there are none.

A backend may have to provision things in the user's repository before its bindings work — labels, a branch. Its file says what, and says to list them and get the user's agreement first. Nothing is created without it.

### Verify

The backend's file ends with how to verify it, and with what writing the bindings may already have created in the user's repository. Follow it, and show the user what came back.

### Write the file

Write `docs/agents/work-tracker.md` — always that path, whatever the existing file was called, because the skills that read it hardcode it.

Follow the rendering rules at the end of `work-tracker-vocabulary.md`, plus what the backend's own file adds at its end. Copy in every command you actually ran and confirmed while writing the bindings.

---

Tell the user setup is done, and name the skills the tracker now serves — the rows of the type table say which.
