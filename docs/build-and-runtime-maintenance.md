# Build and Runtime Maintenance

This document records the reusable workflow for updating the JBR baseline,
building the patched runtime, and selecting it from a JetBrains IDE. Paths use
generic placeholders; no machine-specific usernames or absolute workspace
paths belong in this document.

## Update the upstream baseline

Keep `upstream/` clean and use the maintained target branch from
`upstream.lock`. A safe update sequence is:

```sh
git -C upstream fetch --prune origin jbr25 --tags
git -C upstream checkout --detach origin/jbr25
git -C upstream status --short
git -C upstream describe --tags --always
```

Record the exact commit and, when available, the matching JBR tag in
`upstream.lock`. The outer repository must also record the new submodule
gitlink. Do not replace `jbr25` with `main` implicitly: a newer JDK line is a
baseline migration and requires an intentional decision.

Always run the complete patch verification after changing the baseline:

```sh
./tools/verify.sh
```

The verification worktree is temporary. Never edit or commit source files
inside `upstream/`.

## Repair patches after an upstream refactor

A patch conflict can indicate that the upstream implementation changed shape,
not that the feature disappeared. Inspect both the new source and the patch's
design intent before editing the patch.

For example, the rounded-corner manager changed from a kind/radius switch to a
class hierarchy with `CustomRoundedCorners`. The small-radius customization
therefore had to move from the old enum case to the current string-to-kind
conversion path while preserving the same public behavior.

When adapting a patch:

1. Apply earlier patches and inspect the conflict in the generated worktree.
2. Identify the current semantic insertion point.
3. Rewrite the patch with the smallest change that preserves its intended
   behavior.
4. Run `./tools/verify.sh` again before building.

Do not force an old hunk onto unrelated context merely to make the patch apply.

## Configure and build

`tools/apply-patches.sh` creates a content-keyed generated source tree under
`build/`. Its name includes the upstream commit and patch fingerprint, so a
new source or patch stack intentionally produces a new directory.

Use a complete boot JDK, not a JRE. At minimum, verify that the selected boot
JDK provides `java`, `javac`, `jar`, `jlink`, and `jmod`:

```sh
/path/to/boot-jdk/bin/java -version
/path/to/boot-jdk/bin/javac -version
test -x /path/to/boot-jdk/bin/jar
test -x /path/to/boot-jdk/bin/jlink
test -x /path/to/boot-jdk/bin/jmod
```

Configure and build from the generated source tree:

```sh
cd /path/to/generated/source
bash configure \
  --with-boot-jdk=/path/to/boot-jdk \
  --with-conf-name=linux-x86_64-server-release
make images
```

The JDK image is normally located at:

```text
/path/to/generated/source/build/linux-x86_64-server-release/images/jdk
```

The built image should contain `bin/java`, `release`, and the Wayland native
libraries such as `lib/libawt_wlawt.so`.

### Toolchain warnings

Newer compilers can expose warnings in the upstream source that are promoted
to errors by the default build. If the failure is confirmed to be unrelated to
the patch stack, a local compatibility build can use:

```sh
bash configure \
  --with-boot-jdk=/path/to/boot-jdk \
  --with-conf-name=linux-x86_64-server-release \
  --disable-warnings-as-errors
make clean
make images
```

This is a build-environment workaround, not a source fix. Record the warning
locations and keep the workaround out of the patch stack unless the project
explicitly adopts it.

## Keep the IDE Runtime path stable

The content-keyed build path is useful for reproducibility but inconvenient in
IDE configuration. After a successful build, update the stable link with:

```sh
./tools/update-current-runtime.sh
```

By default it updates:

```text
~/.local/share/jbr-wayland/current
```

The script derives the expected image from the current upstream commit and
patch fingerprint, validates the JDK image, and atomically replaces the
symlink. An explicit image or link location can be supplied when needed:

```sh
./tools/update-current-runtime.sh /path/to/images/jdk
JBR_RUNTIME_LINK=/path/to/stable/current ./tools/update-current-runtime.sh
```

Configure the IDE's product `.jdk` file to contain only the stable link path,
for example:

```text
~/.config/JetBrains/<Product><Version>/<product>.jdk
```

This keeps IDE configuration unchanged across rebuilds. Restart the IDE after
changing the link. The link target can be rolled back by pointing it at a
previous validated `images/jdk` directory.

## Runtime validation and limitations

Before switching an IDE, validate the image directly:

```sh
~/.local/share/jbr-wayland/current/bin/java -version
test -x ~/.local/share/jbr-wayland/current/bin/javac
test -f ~/.local/share/jbr-wayland/current/release
```

A source build may be a plain JBR image rather than the JBR-with-JCEF package
normally distributed with JetBrains IDEs. The IDE may still start, but
embedded-browser features such as Markdown preview or web views require
separate validation. Keep the bundled Runtime available for rollback, and
return to it if the IDE becomes unstable or an IDE update changes its Runtime
requirements.
