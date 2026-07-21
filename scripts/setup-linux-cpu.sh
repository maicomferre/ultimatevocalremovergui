#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python_bin="${PYTHON:-python3}"
venv_dir="${UVR_VENV_DIR:-${repo_dir}/.venv}"

cd "${repo_dir}"

"${python_bin}" scripts/detect-hardware.py

"${python_bin}" -c '
import sys
if sys.version_info < (3, 11):
    raise SystemExit("UVR Linux CPU requires Python 3.11 or newer for the current ONNX Runtime.")
'

if ! "${python_bin}" -c 'import tkinter' 2>/dev/null; then
    echo "Tkinter is missing. Install the python3-tk package for your distribution." >&2
    exit 1
fi

for command_name in ffmpeg rubberband; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "Missing system command: ${command_name}" >&2
        exit 1
    fi
done

"${python_bin}" -m venv "${venv_dir}"
"${venv_dir}/bin/python" -m pip install --upgrade pip
"${venv_dir}/bin/python" -m pip install -r requirements.txt

echo "CPU environment ready. Run: ${venv_dir}/bin/python UVR.py"
