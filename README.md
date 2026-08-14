# JBR Wayland Patch Stack

This repository maintains local Wayland behavior changes for a pinned JBR 25
baseline without forking or modifying the official JetBrainsRuntime history.

The official source lives in the `upstream/` git submodule. The outer
repository owns the ordered patch stack, documentation, and tooling. Patches
are applied to an ignored generated worktree, so the official checkout stays
clean and can be updated independently.

## Current baseline

```text
repository: git@github.com:JetBrains/JetBrainsRuntime.git
branch:     jbr25
tag:        jb25.0.4-b570
commit:     25b665dd51df4873cd9a5e4b40fad07857730d32
```

The baseline is deliberately JBR 25. The upstream `main` branch is a
different, newer JDK line and is not interchangeable with this patch target.

## Repository layout

```text
upstream/                         clean official JBR submodule
patches/                          ordered unified patches
docs/                             design and manual-test notes
tools/apply-patches.sh            create a persistent patched worktree
tools/update-current-runtime.sh   update the stable IDE Runtime symlink
tools/verify.sh                   check and apply the stack temporarily
upstream.lock                     human-readable baseline pin
build/                            ignored generated worktrees and build data
```

## Initialize and verify

```sh
git submodule update --init --checkout
./tools/verify.sh
```

The verification script refuses a dirty official checkout and applies every
patch to a temporary detached worktree. It removes only that temporary
worktree when verification finishes.

## Create a patched source tree

```sh
./tools/apply-patches.sh
```

The script prints the generated source path. Use that path as the JBR source
tree for configuration and builds. The generated worktree is content-keyed by
the upstream commit and patch hashes, so changing a patch creates a new
artifact rather than silently reusing an old source tree.

To reproduce the intended runtime behavior, add this VM option to the IDE:

```text
-Dsun.awt.wl.ShadowPopupsOnly=true
```

The existing `-Dsun.awt.wl.Shadow=false` property remains stronger and still
disables all JBR Wayland shadows.

## Build and select the current IDE Runtime

Configure and build the generated source tree with the normal JBR commands:

```sh
bash configure --with-boot-jdk=/path/to/boot-jdk
make images
```

After a successful build, update the stable user-level Runtime link:

```sh
./tools/update-current-runtime.sh
```

By default, the script finds the image matching the current upstream commit and
patch fingerprint, then atomically updates:

```text
~/.local/share/jbr-wayland/current
```

The target can also be supplied explicitly, and the link location can be
overridden with `JBR_RUNTIME_LINK`:

```sh
./tools/update-current-runtime.sh /path/to/images/jdk
JBR_RUNTIME_LINK=/some/stable/path ./tools/update-current-runtime.sh
```

Configure each IDE's product `.jdk` file to contain only the stable link path,
for example `~/.config/JetBrains/WebStorm2026.2/webstorm.jdk`. The IDE then
keeps the same configuration while new content-keyed builds are selected by
updating one symlink. Restart the IDE after changing the link.

## Patch stack

1. `0001-shadow-popups-only.patch` adds the additive popup-only shadow flag.
2. `0002-popup-shadow-style.patch` adjusts popup shadow rendering.
3. `0003-small-rounded-corners.patch` makes the small rounded-corner radius
   configurable.

See [`docs/wayland-popup-shadow.md`](docs/wayland-popup-shadow.md) for the
original design, expected behavior, build notes, and manual test matrix.

## Updating the official source

Update the submodule only when intentionally moving the patch baseline:

```sh
git -C upstream fetch origin jbr25
git -C upstream checkout --detach <commit>
git -C upstream status --short
```

Then update `upstream.lock`, run `./tools/verify.sh`, repair the patches, and
validate a build before committing the outer repository's submodule pointer.
