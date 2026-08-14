#!/usr/bin/env bash

set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

git -C "$repo_root" submodule update --init --checkout upstream
git -C "$repo_root/upstream" status --short
