#!/usr/bin/env bash

set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
upstream_dir="$repo_root/upstream"
build_root="${JBR_PATCH_BUILD_ROOT:-$repo_root/build/_shared/jbr}"

if ! upstream_commit=$(git -C "$upstream_dir" rev-parse HEAD 2>/dev/null); then
    printf 'The upstream submodule is not initialized. Run tools/bootstrap.sh first.\n' >&2
    exit 1
fi

if [[ -n $(git -C "$upstream_dir" status --porcelain --untracked-files=all) ]]; then
    printf 'The upstream submodule is dirty; refusing to apply patches.\n' >&2
    git -C "$upstream_dir" status --short >&2
    exit 1
fi

shopt -s nullglob
patches=("$repo_root"/patches/*.patch)
if (( ${#patches[@]} == 0 )); then
    printf 'No patches found under %s.\n' "$repo_root/patches" >&2
    exit 1
fi

patch_fingerprint=$(
    for patch_path in "${patches[@]}"; do
        printf '%s  %s\n' "$(git hash-object "$patch_path")" "${patch_path#"$repo_root/"}"
    done | git hash-object --stdin
)

artifact_name="${upstream_commit:0:12}-${patch_fingerprint:0:12}"
artifact_root="$build_root/$artifact_name"
source_dir="$artifact_root/source"
state_file="$artifact_root/.patch-state"

mkdir -p "$build_root"

if [[ -e "$state_file" ]]; then
    expected_state=$(printf '%s\n%s\n' "$upstream_commit" "$patch_fingerprint")
    if [[ $(<"$state_file") == "$expected_state" ]]; then
        printf '%s\n' "$source_dir"
        exit 0
    fi
    printf 'A generated artifact exists with a mismatched state: %s\n' "$artifact_root" >&2
    exit 1
fi

if [[ -e "$artifact_root" ]]; then
    printf 'An incomplete generated artifact exists: %s\n' "$artifact_root" >&2
    printf 'Remove it after confirming no build is using it, then retry.\n' >&2
    exit 1
fi

mkdir -p "$artifact_root"
git -C "$upstream_dir" worktree add --detach "$source_dir" "$upstream_commit"

for patch_path in "${patches[@]}"; do
    printf 'Applying %s\n' "${patch_path#"$repo_root/"}"
    git -C "$source_dir" apply --3way --whitespace=nowarn "$patch_path"
done

printf '%s\n%s\n' "$upstream_commit" "$patch_fingerprint" > "$state_file"
printf '%s\n' "$source_dir"
