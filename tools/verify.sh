#!/usr/bin/env bash

set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
upstream_dir="$repo_root/upstream"

if ! upstream_commit=$(git -C "$upstream_dir" rev-parse HEAD 2>/dev/null); then
    printf 'The upstream submodule is not initialized. Run tools/bootstrap.sh first.\n' >&2
    exit 1
fi

if [[ -n $(git -C "$upstream_dir" status --porcelain --untracked-files=all) ]]; then
    printf 'The upstream submodule is dirty; refusing to verify patches.\n' >&2
    git -C "$upstream_dir" status --short >&2
    exit 1
fi

shopt -s nullglob
patches=("$repo_root"/patches/*.patch)
if (( ${#patches[@]} == 0 )); then
    printf 'No patches found under %s.\n' "$repo_root/patches" >&2
    exit 1
fi

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/jbr-wayland-verify.XXXXXX")
temporary_source="$temporary_root/source"
cleanup() {
    git -C "$upstream_dir" worktree remove --force "$temporary_source" >/dev/null 2>&1 || true
    rmdir "$temporary_root" >/dev/null 2>&1 || true
}
trap cleanup EXIT

git -C "$upstream_dir" worktree add --detach "$temporary_source" "$upstream_commit" >/dev/null

for patch_path in "${patches[@]}"; do
    printf 'Checking %s\n' "${patch_path#"$repo_root/"}"
    git -C "$temporary_source" apply --check --3way --whitespace=nowarn "$patch_path"
    git -C "$temporary_source" apply --3way --whitespace=nowarn "$patch_path"
done

git -C "$temporary_source" diff --check
printf 'Patch stack applies cleanly to %s.\n' "$upstream_commit"
