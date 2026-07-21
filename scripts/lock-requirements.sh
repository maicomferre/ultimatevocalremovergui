#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cache_dir="${UVR_UV_CACHE_DIR:-${repo_dir}/.cache/uv}"

cd "${repo_dir}"
mkdir -p "${cache_dir}"

UV_CACHE_DIR="${cache_dir}" uv pip compile \
    --python-version 3.14 \
    --python-platform x86_64-manylinux_2_28 \
    --extra-index-url https://download.pytorch.org/whl/cpu \
    --index-strategy unsafe-best-match \
    --emit-index-url \
    --emit-index-annotation \
    --upgrade \
    --output-file requirements/linux-cpu.txt \
    requirements/linux-cpu.in
