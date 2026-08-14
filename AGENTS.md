# JBR Wayland Patch Maintenance

This repository owns a small, reproducible patch stack for JetBrains Runtime
Wayland behavior. The official JBR source is an upstream dependency; the
maintained artifacts here are the patch files, documentation, scripts, and
agent rules.

## Repository invariants

- Keep `upstream/` as an initialized, clean git submodule. It is pinned by the
  gitlink committed in this repository and documented in `upstream.lock`.
- Never edit or commit local changes inside `upstream/`. Do not create local
  commits there. The official checkout must remain suitable for resetting and
  updating from JetBrainsRuntime.
- Apply patches only to a generated worktree under ignored `build/`. Never
  commit a patched copy of the JBR source tree here.
- Keep every source change represented by an ordered patch under `patches/`.
  Lexical order is application order; use numeric prefixes and keep patches
  grouped by purpose.
- Keep design notes and manual-test results under `docs/`. Do not put build
  logs or generated source trees under version control.
- Do not force a patch onto a different upstream baseline. First update the
  pinned submodule intentionally, then repair and verify the patch stack.
- Use Conventional Commits with English messages. Do not create a commit
  unless the user requests one.

## Normal workflow

```sh
git submodule update --init --checkout
./tools/verify.sh
./tools/apply-patches.sh
```

`tools/verify.sh` checks the clean upstream checkout and applies the complete
stack to a temporary worktree. `tools/apply-patches.sh` creates a persistent,
ignored patched worktree for building and manual testing.

## Updating the upstream baseline

The current patch stack targets JBR 25 (`jbr25`, `jb25.0.4-b570`). Do not
replace it with the repository's newer `main` line unless the patch target is
intentionally migrated.

When an update is intended:

1. Fetch the desired upstream revision.
2. Check out that revision in `upstream/` and ensure it is clean.
3. Update `upstream.lock` and the outer repository's submodule gitlink.
4. Run `./tools/verify.sh` and repair patches in order if necessary.
5. Build and run the relevant Wayland tests before committing.
