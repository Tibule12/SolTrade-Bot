#!/usr/bin/env python3
"""Type a secret into the focused X11 window without placing it in argv."""

import ctypes
import getpass
import os
import sys
import time


X11 = ctypes.cdll.LoadLibrary("libX11.so.6")
XTST = ctypes.cdll.LoadLibrary("libXtst.so.6")

X11.XOpenDisplay.restype = ctypes.c_void_p
X11.XStringToKeysym.argtypes = [ctypes.c_char_p]
X11.XStringToKeysym.restype = ctypes.c_ulong
X11.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
X11.XKeysymToKeycode.restype = ctypes.c_uint
XTST.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]


def key(display: int, name: str, down: bool) -> None:
    keysym = X11.XStringToKeysym(name.encode("ascii"))
    keycode = X11.XKeysymToKeycode(display, keysym)
    if not keycode:
        raise RuntimeError(f"No keycode for {name!r}")
    XTST.XTestFakeKeyEvent(display, keycode, int(down), 0)


def main() -> None:
    secret = getpass.getpass("Secret: ")
    delay = float(os.environ.get("X11_TYPE_DELAY", "0.025"))
    display = X11.XOpenDisplay(None)
    if not display:
        raise RuntimeError("Unable to open X11 display")
    time.sleep(0.3)
    for char in secret:
        shifted = char.isupper() or char in '~!@#$%^&*()_+{}|:\"<>?'
        name = char.lower() if char.isalpha() else char
        if shifted:
            key(display, "Shift_L", True)
        key(display, name, True)
        time.sleep(min(0.025, delay / 3))
        key(display, name, False)
        if shifted:
            key(display, "Shift_L", False)
        X11.XFlush(display)
        time.sleep(delay)
    secret = ""
    if "--no-enter" not in sys.argv[1:]:
        key(display, "Return", True)
        key(display, "Return", False)
        X11.XFlush(display)


if __name__ == "__main__":
    main()
