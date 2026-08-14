#!/usr/bin/env bash

set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
upstream_dir="$repo_root/upstream"
build_root="${JBR_PATCH_BUILD_ROOT:-$repo_root/build/_shared/jbr}"
build_configuration="${JBR_BUILD_CONFIGURATION:-linux-x86_64-server-release}"

if (( $# > 1 )); then
    printf 'Usage: %s [jdk-image]\n' "$0" >&2
    exit 2
fi

if ! user_home=$(getent passwd "$(id -u)" | cut -d: -f6); then
    printf 'Could not determine the current user home directory.\n' >&2
    exit 1
fi
if [[ -z "$user_home" ]]; then
    printf 'The current user has no home directory.\n' >&2
    exit 1
fi

if ! upstream_commit=$(git -C "$upstream_dir" rev-parse HEAD 2>/dev/null); then
    printf 'The upstream submodule is not initialized. Run tools/bootstrap.sh first.\n' >&2
    exit 1
fi

if [[ -n $(git -C "$upstream_dir" status --porcelain --untracked-files=all) ]]; then
    printf 'The upstream submodule is dirty; refusing to update the runtime link.\n' >&2
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

default_runtime_image="$build_root/${upstream_commit:0:12}-${patch_fingerprint:0:12}/source/build/$build_configuration/images/jdk"
runtime_image=${1:-$default_runtime_image}
if [[ ! -d "$runtime_image" || ! -x "$runtime_image/bin/java" || ! -f "$runtime_image/release" ]]; then
    printf 'JDK image is missing or invalid: %s\n' "$runtime_image" >&2
    printf 'Build it first with make images, or pass an explicit JDK image path.\n' >&2
    exit 1
fi
runtime_image=$(CDPATH= cd -- "$runtime_image" && pwd -P)

runtime_link="${JBR_RUNTIME_LINK:-$user_home/.local/share/jbr-wayland/current}"
runtime_parent=$(dirname -- "$runtime_link")
mkdir -p "$runtime_parent"

if [[ -e "$runtime_link" && ! -L "$runtime_link" ]]; then
    printf 'Refusing to replace a non-symlink runtime path: %s\n' "$runtime_link" >&2
    exit 1
fi

temporary_link="${runtime_link}.tmp.$$"
cleanup() {
    if [[ -L "$temporary_link" ]]; then
        rm -f -- "$temporary_link"
    fi
}
trap cleanup EXIT

ln -s -- "$runtime_image" "$temporary_link"
mv -Tf -- "$temporary_link" "$runtime_link"
trap - EXIT

printf 'Runtime link: %s\n' "$runtime_link"
printf 'Target: %s\n' "$runtime_image"
