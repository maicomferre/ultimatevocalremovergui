#!/usr/bin/env python3
"""Generate standard Hicolor application icons from the original UVR icon."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


ICON_SIZES = (16, 24, 32, 48, 64, 128, 256, 512, 1024)
ICON_NAME = "ultimate-vocal-remover.png"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("hicolor_root", type=Path)
    args = parser.parse_args()

    with Image.open(args.source) as source:
        source = source.convert("RGBA")
        for size in ICON_SIZES:
            icon_dir = args.hicolor_root / f"{size}x{size}" / "apps"
            icon_dir.mkdir(parents=True, exist_ok=True)
            icon = source.resize((size, size), Image.Resampling.LANCZOS)
            icon.save(icon_dir / ICON_NAME, format="PNG", optimize=True)


if __name__ == "__main__":
    main()
