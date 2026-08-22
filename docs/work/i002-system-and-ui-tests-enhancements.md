---
title: System and UI tests enhancements
state: todo
---

## 1. Generate the `ui-*` targets from dockerfile stages

**Problem.** `Makefile` hand-writes three near-identical blocks — `ui-`, `ui-zsh-`, `ui-tmux-` — while the `with-basics` and `with-asdf` stages get no UI target at all. `with-asdf` is the interesting one: asdf installed but deliberately off PATH, which is the whole reason `activate_asdf` exists in `deploy.sh`.

**Idea.** Derive the stage list from the dockerfile the same way `_image_names` is already derived from filenames (`sed -nE '/^FROM.* AS (.+)/I s//\1/p'`, which the image build rule already runs), and emit one pattern rule:

```
make ui-ubuntu-with-asdf
make ui-ubuntu-with-basics
```

**Why it is worth it.** Replaces three copied blocks with one rule, covers every stage automatically including new ones, and stops the target list from drifting out of sync with the dockerfiles.

**Related, same area:**

 - **Default to `with-basics`, keep `base` as an explicit `ui-bare-*`.** Measured on this machine: `base` takes 7.4s and prints 108 lines; `with-basics` takes 0.9s and prints 4. The basic-packages install is almost never what is being iterated on. (The `quietly` change already landed cuts the noise side of this; the time cost remains.)
 - **Drop `.PHONY` from the image targets** (`Makefile`, `.PHONY: $(_image_names)`) or gate them behind a stamp file. Because they are phony, every `make ui-*` shells out six cached `docker build` calls first — a measured **4.9s** of pure overhead before the container even starts.
 - **Add a `KEEP=1` escape hatch** that drops `--rm` and names the container, so a scripted run's `/home/amy` can be inspected afterwards with `docker exec`. The interactive targets already drop to a shell; scripted ones throw the evidence away.

---

## 2. System tests cannot run from a git worktree

**Observed while implementing item 3, not related to it.** Every assertion in `git/test_install_git.system.sh` fails when the suite runs from a linked worktree instead of the main clone, each one preceded by:

```
fatal: not a git repository: /home/barreto/dotfiles/.git/worktrees/dotfiles
```

**Root cause.** In a linked worktree `.git` is a *file* containing `gitdir: <path into the main clone>`, not a directory. `run_test_in_docker` mounts the repo at `/app`, so the pointer travels into the container but its target does not exist there, and git then refuses to operate on `/app` at all. Nothing to do with the installer under test.

**Idea.** Either mount the real gitdir alongside `/app` so the pointer resolves, or stop leaning on the mounted repo altogether and have the test `git init` a scratch repo under `$SHUNIT_TMPDIR`. The test is about the installer's templates, hooks and config, none of which need *this* repo specifically.

**Why it is worth it.** Worktrees are how this repo's own feature branches get developed, so the suite is red for exactly the checkouts most likely to run it — and a genuinely broken git installer would be indistinguishable from the standing noise.

**Watch out for.** The scratch-repo option narrows coverage slightly: it would no longer catch a regression that depends on the dotfiles repo's own git state. Probably fine, but worth deciding deliberately rather than by accident.
