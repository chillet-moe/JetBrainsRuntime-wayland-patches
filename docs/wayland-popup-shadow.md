# JBR Wayland popup-only shadows

This document records the design, build notes, and manual verification matrix
for the patch stack in the parent repository. The source baseline is pinned by
the parent repository's `upstream` submodule; the patches are applied to a
generated worktree rather than to that clean submodule.

## Goal

Modify JetBrains Runtime (JBR) Wayland AWT so that, on GNOME/Mutter, JetBrains IDE main windows do **not** draw their own client-side Wayland shadow, while Swing/AWT popup windows such as context menus, dropdowns, and completion popups can still keep JBR-drawn shadows.

The intended runtime flag is:

```text
-Dsun.awt.wl.ShadowPopupsOnly=true
```

This flag must be additive and backward-compatible. Existing behavior must remain unchanged when the flag is absent.

## Context

Current observed behavior:

- On GNOME 50 + native Wayland JetBrains IDE, the main IDE window shadow is drawn by JBR as part of the Wayland client surface/subsurface behavior.
- Adding `-Dsun.awt.wl.Shadow=false` stops the main window shadow and allows GNOME extensions such as Rounded Window Corners Reborn to handle the main window, but it also removes shadows from menus/popups.
- On niri or other wlroots-like compositors, default behavior may differ because the compositor may expose server-side decoration or no-CSD/tiled-state paths.

Relevant JBR source areas:

- `src/java.desktop/unix/classes/sun/awt/wl/WLComponentPeer.java`
  - Current global shadow gate: `sun.awt.wl.Shadow` / `shadowEnabled`.
  - Current constructor creates `ShadowImpl` when `dropShadow && shadowEnabled`.
  - Current code already distinguishes popup vs non-popup through `targetIsWlPopup()`.
  - Current code already has separate shadow sizes: `ShadowImage.WINDOW_SHADOW_SIZE` and `ShadowImage.POPUP_SHADOW_SIZE`.
- `src/java.desktop/unix/classes/sun/awt/wl/WLDecoratedPeer.java`
  - Decoration mode selection: `DEFAULT`, `GTK`, `SERVER`.
  - `SERVER` depends on `WLToolkit.isSSDAvailable()`.
- `src/java.desktop/unix/classes/sun/awt/wl/WLToolkit.java`
  - `isSSDAvailable()` reflects compositor support for server-side decoration.

Do not attempt to solve this by forcing server-side decoration on GNOME. Mutter usually does not expose the required SSD path for this use case.

## Desired behavior

When no new flag is passed:

```text
-Dsun.awt.wl.ShadowPopupsOnly is absent
```

Behavior must remain exactly as before.

When this is passed:

```text
-Dsun.awt.wl.ShadowPopupsOnly=true
```

Expected behavior:

- Toplevel IDE windows: no JBR shadow.
- Normal dialogs: no JBR shadow, unless they are actually `Window.Type.POPUP`.
- `Window.Type.POPUP` surfaces: keep JBR shadow.
- `-Dsun.awt.wl.Shadow=false` remains stronger and disables all JBR Wayland shadows, including popup shadows.

In pseudo-logic:

```java
boolean isWlPopup = targetIsWlPopup();
boolean shouldCreateShadow = dropShadow
        && shadowEnabled
        && (!shadowPopupsOnly || isWlPopup);
```

## Non-goals

Do not rewrite the shadow rendering algorithm.

Do not change `ShadowImage`, `ShadowImpl`, `WLSubSurface`, or Wayland native protocol code unless compilation requires it.

Do not change GTK/default/server decoration selection.

Do not repurpose `sun.awt.wl.Shadow` into a string enum. Existing users may already pass `true` or `false`, and `Boolean.parseBoolean(...)` semantics must not be broken.

Do not remove WSL default behavior. If `shadowEnabled` is false because JBR disabled shadows by default in WSL, the new flag must not re-enable them.

## Implementation plan

### 1. Select a JBR 25 baseline

The target IDE currently reports:

```text
Runtime version: 25.0.3+9-b508.16 amd64
```

Use a JBR 25 baseline for the patch. Exact build matching is optional:

- Preferred general baseline: `jbr25` or the closest current JBR 25 branch available locally.
- Current selected baseline: `jb25.0.4-b570`
  (`25b665dd51df4873cd9a5e4b40fad07857730d32`).
- Do not use `main` for the IDE runtime deliverable if it points at a newer JDK line such as JDK 27.

The patch is intentionally small and should be easy to cherry-pick between JBR 25 branches/tags.

### 2. Test that the chosen baseline can compile before editing

Before changing source code, verify that the selected JBR 25 baseline can be configured and at least compile the affected desktop module in the current environment.

Recommended commands:

```bash
bash configure
make java.desktop
```

If a full image build is reasonably available, also run:

```bash
make images
```

If the baseline does not configure or compile before the patch, stop and report the environment/build failure separately from the popup-shadow change. Do not mix infrastructure failures with patch regressions.

### 3. Inspect the current source before editing

Run:

```bash
grep -R "sun.awt.wl.Shadow" -n src/java.desktop/unix/classes/sun/awt/wl
grep -R "targetIsWlPopup" -n src/java.desktop/unix/classes/sun/awt/wl
grep -R "WINDOW_SHADOW_SIZE\|POPUP_SHADOW_SIZE" -n src/java.desktop/unix/classes/sun/awt/wl
```

Confirm that the constructor in `WLComponentPeer.java` still contains logic equivalent to:

```java
if (dropShadow && shadowEnabled) {
    shadow = new ShadowImpl(targetIsWlPopup()
            ? ShadowImage.POPUP_SHADOW_SIZE
            : ShadowImage.WINDOW_SHADOW_SIZE);
} else {
    shadow = new NilShadow();
}
```

If the code has moved, locate the current shadow creation point and adapt the same logic there.

### 4. Explain how the resulting runtime will be applied to the IDE

Before modifying source, document the runtime application path so the user can decide whether a full replacement runtime is acceptable.

In the IDE:

```text
Help | Edit Custom VM Options...
```

Remove:

```text
-Dsun.awt.wl.Shadow=false
```

Add:

```text
-Dsun.awt.wl.ShadowPopupsOnly=true
```

Ensure Wayland toolkit is active. In `Help | About`, confirm something equivalent to:

```text
Toolkit: sun.awt.wl.WLToolkit
```

After the patched JBR image is built, select it through:

```text
Help | Find Action... | Choose Boot Java Runtime for the IDE... | Add Custom Runtime...
```

Choose the built JDK image, usually:

```text
build/<configuration>/images/jdk
```

Runtime caveat: a locally built plain JBR image may not include the same JCEF payload as the IDE-bundled runtime. If the IDE relies on embedded browser features, validate Markdown preview and other web views after switching runtimes.

### 5. Add a new additive property

In `WLComponentPeer.java`, near the existing `shadowEnabled` field, add:

```java
private static final boolean shadowPopupsOnly =
        Boolean.getBoolean("sun.awt.wl.ShadowPopupsOnly");
```

Then replace the shadow construction block with:

```java
boolean isWlPopup = targetIsWlPopup();
if (dropShadow && shadowEnabled && (!shadowPopupsOnly || isWlPopup)) {
    shadow = new ShadowImpl(isWlPopup
            ? ShadowImage.POPUP_SHADOW_SIZE
            : ShadowImage.WINDOW_SHADOW_SIZE);
} else {
    shadow = new NilShadow();
}
```

Keep the old `sun.awt.wl.Shadow` initializer unchanged.

### 6. Optional diagnostic logging

If useful during manual testing, add temporary fine-level logging only. Remove it before the final patch unless the project already has an accepted debug logging style.

Temporary example:

```java
if (log.isLoggable(Level.FINE)) {
    log.fine("WL shadow decision: target=" + target
            + ", dropShadow=" + dropShadow
            + ", shadowEnabled=" + shadowEnabled
            + ", shadowPopupsOnly=" + shadowPopupsOnly
            + ", isWlPopup=" + isWlPopup);
}
```

Do not leave noisy logging enabled by default.

## Expected diff shape

The final patch should be close to this:

```diff
diff --git a/src/java.desktop/unix/classes/sun/awt/wl/WLComponentPeer.java b/src/java.desktop/unix/classes/sun/awt/wl/WLComponentPeer.java
--- a/src/java.desktop/unix/classes/sun/awt/wl/WLComponentPeer.java
+++ b/src/java.desktop/unix/classes/sun/awt/wl/WLComponentPeer.java
@@
-    private static final boolean shadowEnabled;
+    private static final boolean shadowEnabled;
+    private static final boolean shadowPopupsOnly =
+            Boolean.getBoolean("sun.awt.wl.ShadowPopupsOnly");
@@
-        if (dropShadow && shadowEnabled) {
-            shadow = new ShadowImpl(targetIsWlPopup() ? ShadowImage.POPUP_SHADOW_SIZE : ShadowImage.WINDOW_SHADOW_SIZE);
+        boolean isWlPopup = targetIsWlPopup();
+        if (dropShadow && shadowEnabled && (!shadowPopupsOnly || isWlPopup)) {
+            shadow = new ShadowImpl(isWlPopup ? ShadowImage.POPUP_SHADOW_SIZE : ShadowImage.WINDOW_SHADOW_SIZE);
         } else {
             shadow = new NilShadow();
         }
```

Formatting should match the surrounding source style.

## Build strategy

### Preferred: full JBR build

Use this if the agent has enough time and disk space.

On Linux, install the dependencies requested by the JBR README for the current branch, then run:

```bash
bash configure
make images
```

Expected output is under a directory similar to:

```text
build/linux-x86_64-server-release/images/jdk
```

For JetBrains IDE usage, prefer a JBR/JBRSDK build flavor compatible with the IDE. Note that JetBrains IDEs normally bundle a JBR-with-JCEF flavor, so a plain custom JBR may affect embedded-browser features such as Markdown preview or some web views.

### Fast validation option: patch-module prototype

If full JBR build is too heavy, create a prototype using `--patch-module=java.desktop=/path/to/patch`. This is acceptable only for local validation.

Do not present `--patch-module` as the final robust distribution method unless explicitly requested; it is sensitive to exact class version and module internals.

## Runtime configuration for manual test

Use the IDE runtime application steps documented above, then run the manual checks below.

## Test matrix

Test on GNOME 50 / Mutter / Wayland first.

### Baseline A: unpatched JBR, default settings

Expected:

- Main IDE window has JBR-drawn shadow.
- Rounded Window Corners Reborn sees a larger rectangle or cannot cleanly handle the main window.
- Menus and popups have JBR shadows.

### Baseline B: unpatched JBR with global shadow disabled

VM option:

```text
-Dsun.awt.wl.Shadow=false
```

Expected:

- Main window shadow is gone.
- GNOME extension can handle the main window better.
- Menus/popups also lose shadows.

### Patched behavior: popup-only mode

VM option:

```text
-Dsun.awt.wl.ShadowPopupsOnly=true
```

Expected:

- Main IDE frame has no JBR shadow.
- Settings dialog and other normal dialogs have no JBR shadow.
- Right-click menu has shadow.
- Main menu dropdown has shadow.
- Completion popup has shadow if it is implemented as a Wayland popup / `Window.Type.POPUP`.
- GNOME Rounded Window Corners Reborn can handle main window rounded corners/shadow without seeing the old JBR main-window shadow.

### Compatibility test: default behavior unchanged

Run patched JBR without the new flag.

Expected:

- Behavior matches upstream JBR.
- Main window still gets the existing JBR shadow.
- Popup/menu shadow still works.

### Compatibility test: global shadow false still wins

Run patched JBR with:

```text
-Dsun.awt.wl.Shadow=false
-Dsun.awt.wl.ShadowPopupsOnly=true
```

Expected:

- No JBR shadows anywhere.
- This confirms that the old global disabling semantics remain stronger than the new popup-only filter.

### Optional compositor comparison

Run on niri or KDE Wayland.

Expected:

- No regression in default mode.
- `ShadowPopupsOnly=true` still suppresses JBR shadows for non-popup windows.
- If server-side decoration is negotiated, confirm the new flag does not break decoration creation.

## Manual verification checklist

Use screenshots or screen recording for each item.

- Main IDE window on GNOME default mode.
- Main IDE window on GNOME with `Shadow=false`.
- Main IDE window on GNOME with `ShadowPopupsOnly=true`.
- Right-click editor context menu with `ShadowPopupsOnly=true`.
- Top menu dropdown with `ShadowPopupsOnly=true`.
- Code completion popup with `ShadowPopupsOnly=true`.
- Settings dialog with `ShadowPopupsOnly=true`.
- GNOME overview / window switcher boundary with `ShadowPopupsOnly=true`.

## Rollback

If the IDE fails to start after selecting a custom runtime:

- Remove the custom runtime selection by deleting the relevant `idea.jdk` / `idea64.jdk` file from the IDE configuration directory, or use `Choose Boot Java Runtime for the IDE...` and select default runtime if the IDE still opens.
- Remove `-Dsun.awt.wl.ShadowPopupsOnly=true` from custom VM options.
- Revert the JBR patch with `git restore` or `git revert`.

## Final deliverables expected from Codex

Produce all of the following:

1. A minimal git diff against the selected JBR branch.
2. A short note naming the exact branch/tag patched.
3. Build commands used, or a clear statement if full build was skipped.
4. Test commands and manual test results.
5. Any runtime caveats, especially whether the custom runtime includes JCEF.
6. Exact IDE VM options to use:

```text
-Dsun.awt.wl.ShadowPopupsOnly=true
```

## Success criteria

The patch is successful only if all are true:

- Without the new flag, behavior is unchanged.
- With `ShadowPopupsOnly=true`, the main IDE window no longer has JBR-drawn shadow on GNOME Wayland.
- With `ShadowPopupsOnly=true`, right-click/menu popup shadows remain visible when those popups are implemented as `Window.Type.POPUP`.
- With `Shadow=false`, all JBR Wayland shadows are still disabled.
- No startup crash or obvious rendering regression occurs in native Wayland mode.
