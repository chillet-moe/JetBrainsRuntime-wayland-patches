# Wayland fractional scaling

## Problem

Before this patch, the Wayland backend exposed only the integer
`wl_output.scale` to Java2D. At a desktop scale of 250%, that normally means a
3x backing buffer followed by compositor downsampling to 2.5x. Font hinting and
rasterization therefore happen for the wrong pixel grid, which can make text
less clear than rendering directly at the fractional scale.

## Design

`0004-fractional-scale-v1.patch` adds the staging
`fractional-scale-v1.xml` protocol to JBR's generated Wayland bindings and
optionally binds `wp_fractional_scale_manager_v1`. Each `wl_surface` gets a
`wp_fractional_scale_v1` object when the compositor advertises the protocol.
The protocol's `preferred_scale` numerator is converted using the mandated
denominator of 120.

Java's `GraphicsConfiguration` needs the correct transform before the first
surface callback so text is rasterized at the fractional pixel grid from the
start. The initial effective scale is consequently derived from the ratio of
the output's physical-mode diagonal to its logical diagonal and snapped to a
1/120 step. The value is accepted only when it is consistent with the
integer `wl_output.scale`; malformed or unavailable metrics fall back to the
integer value.

When a surface is wholly on one output, later `preferred_scale` feedback can
update that output's effective scale and recreate its graphics configurations.
A surface spanning multiple outputs does not overwrite any shared output
configuration from per-surface feedback; ordinary enter/leave processing
selects the output with the greatest effective scale.

Backing-buffer dimensions use `ceil(logicalSize * effectiveScale)`. The
existing `wp_viewporter` destination remains the logical surface size, so the
compositor maps the fractional-size buffer without the old integer-scale
downsample. This applies to both the shared-memory and Vulkan surface paths.

`0005-fractional-scale-image-copy.patch` keeps Swing's same-scale back-buffer
source-region copies pixel-exact. The optimization is deliberately limited to
the source-region `drawImage` overload used for partial back-buffer copies;
ordinary positioned and sized image drawing retains its existing HiDPI image
and resolution-variant handling. Without the patch, `SunGraphics2D` sends a
fractionally scaled back buffer through the generic image-scaling path, where
separate source and destination rounding can move content by a pixel during
partial repaint.

`0006-defer-incomplete-frame-commits.patch` prevents partially painted content
from reaching Wayland. Swing updates the native window only after its outermost
double-buffered paint has ended, and the native buffer manager does not publish
new damage from a frame callback until Java has committed that complete frame.
Together these address the common transient-content movement tracked as
JBR-7203 and JBR-7204; neither issue is a change in the top-level window's
logical size.

If `wp_fractional_scale_manager_v1` is absent, the per-surface protocol object
is not created. Integer scaling remains the fallback. An explicit
`sun.java2d.uiScale` debug override also remains authoritative.

## Verification

The implementation can be checked without connecting to the user's active
Wayland session:

1. Run `./tools/verify.sh` to apply the complete patch stack to a temporary
   clean worktree.
2. Configure a generated worktree with a JDK 25 boot JDK and development
   headers, then build `java.desktop-gensrc-only` and
   `java.desktop-java-only`.
3. Generate `java.desktop-libs-compile-commands` and compile the changed
   `WLSurface.c`, `WLToolkit.c`, `WLSMSurfaceData.c`, and `WLBuffers.c` entries
   with their exact generated commands.
4. Run `WLFractionalScaleMetrics` and `SameScaleImageCopy` headlessly. The
   latter verifies raw backing-buffer pixels after same-scale copies at 1.25x,
   1.5x, 2x, and 2.5x; neither test connects to a display server.

Interactive rendering validation should be done later in a disposable nested
Wayland compositor, checking at least 125%, 200%, and 250%, mixed-scale output
transitions, shared-memory rendering, Vulkan rendering, popups, and shadows.
