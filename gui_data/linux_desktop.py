"""Linux desktop integration helpers."""

from __future__ import annotations

import ctypes
import os
from pathlib import Path
from tkinter import Misc

from PIL import Image


def set_x11_window_icon(window: Misc, icon_path: str | os.PathLike[str]) -> bool:
    """Publish a window icon for X11 and XWayland desktop environments."""
    if not os.environ.get("DISPLAY"):
        return False

    display = None
    try:
        x11 = ctypes.CDLL("libX11.so.6")
        x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
        x11.XOpenDisplay.restype = ctypes.c_void_p
        x11.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
        x11.XInternAtom.restype = ctypes.c_ulong
        x11.XChangeProperty.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ulong,
            ctypes.c_ulong,
            ctypes.c_ulong,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.POINTER(ctypes.c_ubyte),
            ctypes.c_int,
        ]
        x11.XChangeProperty.restype = ctypes.c_int
        x11.XQueryTree.argtypes = [
            ctypes.c_void_p,
            ctypes.c_ulong,
            ctypes.POINTER(ctypes.c_ulong),
            ctypes.POINTER(ctypes.c_ulong),
            ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)),
            ctypes.POINTER(ctypes.c_uint),
        ]
        x11.XQueryTree.restype = ctypes.c_int
        x11.XFree.argtypes = [ctypes.c_void_p]
        x11.XFlush.argtypes = [ctypes.c_void_p]
        x11.XCloseDisplay.argtypes = [ctypes.c_void_p]

        display = x11.XOpenDisplay(None)
        if not display:
            return False

        icon_values = []
        with Image.open(Path(icon_path)) as source:
            source = source.convert("RGBA")
            for size in (128, 64, 48, 32, 24, 16):
                icon = source.resize((size, size), Image.Resampling.LANCZOS)
                icon_values.extend((size, size))
                icon_values.extend(
                    (alpha << 24) | (red << 16) | (green << 8) | blue
                    for red, green, blue, alpha in icon.getdata()
                )

        values = (ctypes.c_ulong * len(icon_values))(*icon_values)
        icon_atom = x11.XInternAtom(display, b"_NET_WM_ICON", False)
        cardinal_atom = x11.XInternAtom(display, b"CARDINAL", False)

        root_window = ctypes.c_ulong()
        parent_window = ctypes.c_ulong()
        children = ctypes.POINTER(ctypes.c_ulong)()
        child_count = ctypes.c_uint()
        client_window = window.winfo_id()
        if x11.XQueryTree(
            display,
            client_window,
            ctypes.byref(root_window),
            ctypes.byref(parent_window),
            ctypes.byref(children),
            ctypes.byref(child_count),
        ):
            if children:
                x11.XFree(children)
            if parent_window.value != root_window.value:
                client_window = parent_window.value

        result = x11.XChangeProperty(
            display,
            client_window,
            icon_atom,
            cardinal_atom,
            32,
            0,
            ctypes.cast(values, ctypes.POINTER(ctypes.c_ubyte)),
            len(icon_values),
        )
        x11.XFlush(display)
        return result == 1
    except (OSError, ValueError, TypeError):
        return False
    finally:
        if display:
            x11.XCloseDisplay(display)
