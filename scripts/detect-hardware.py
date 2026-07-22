#!/usr/bin/env python3
"""Report Linux accelerator capabilities without changing the host system."""

from __future__ import annotations

import argparse
import json
import platform
from pathlib import Path
import shutil
import subprocess


PCI_VENDORS = {
    "0x1002": "amd",
    "0x10de": "nvidia",
    "0x8086": "intel",
}


def read_gpu_vendors() -> list[str]:
    vendors: set[str] = set()
    for vendor_file in Path("/sys/class/drm").glob("card*/device/vendor"):
        try:
            vendor_id = vendor_file.read_text(encoding="ascii").strip().lower()
        except OSError:
            continue
        vendors.add(PCI_VENDORS.get(vendor_id, vendor_id))
    return sorted(vendors)


def nvidia_status() -> dict[str, object]:
    executable = shutil.which("nvidia-smi")
    result: dict[str, object] = {
        "command": executable,
        "driver_available": False,
        "gpus": [],
    }
    if executable is None:
        return result

    command = [
        executable,
        "--query-gpu=name,driver_version",
        "--format=csv,noheader,nounits",
    ]
    try:
        completed = subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return result

    result["driver_available"] = True
    result["gpus"] = [
        line.strip() for line in completed.stdout.splitlines() if line.strip()
    ]
    return result


def detect() -> dict[str, object]:
    vendors = read_gpu_vendors()
    nvidia = nvidia_status()
    rocm_device = Path("/dev/kfd").exists()

    reasons = ["Only the tested CPU dependency profile is currently published."]
    if nvidia["driver_available"]:
        reasons.append("NVIDIA hardware is visible; CUDA remains disabled until its own lock is tested.")
    if "amd" in vendors or rocm_device:
        reasons.append("AMD hardware is visible; ROCm remains disabled until its own lock is tested.")

    return {
        "system": platform.system().lower(),
        "architecture": platform.machine().lower(),
        "gpu_vendors": vendors,
        "nvidia": nvidia,
        "rocm_device": rocm_device,
        "selected_profile": "linux-cpu",
        "selection_reasons": reasons,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    args = parser.parse_args()
    report = detect()

    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
        return 0

    print(f"System: {report['system']} ({report['architecture']})")
    print(f"GPU vendors: {', '.join(report['gpu_vendors']) or 'none detected'}")
    print(f"NVIDIA driver available: {report['nvidia']['driver_available']}")
    print(f"ROCm device available: {report['rocm_device']}")
    print(f"Selected dependency profile: {report['selected_profile']}")
    for reason in report["selection_reasons"]:
        print(f"- {reason}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
