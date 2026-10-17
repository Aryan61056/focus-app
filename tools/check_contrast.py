#!/usr/bin/env python3
"""Contrast check for the native color tokens (mac/Sources/FocusUI/Tokens.swift), light and dark.
Text needs 4.5:1, non-text marks (the ring) need 3:1. Exits 1 on any failure. Reads the Swift file so it cannot drift."""
from __future__ import annotations
import re, sys, pathlib

SRC = pathlib.Path(__file__).resolve().parent.parent / "mac/Sources/FocusUI/Tokens.swift"
PAT = re.compile(r"static let (\w+) = Color\(light: 0x([0-9A-Fa-f]{6}), dark: 0x([0-9A-Fa-f]{6})(?:, lightAlpha: ([\d.]+), darkAlpha: ([\d.]+))?\)")

def lin(c): c /= 255; return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
def lum(rgb): return 0.2126 * lin(rgb[0]) + 0.7152 * lin(rgb[1]) + 0.0722 * lin(rgb[2])
def ratio(a, b): la, lb = sorted([lum(a), lum(b)], reverse=True); return (la + 0.05) / (lb + 0.05)
def rgb(h): return ((h >> 16) & 255, (h >> 8) & 255, h & 255)
def over(fg, a, bg): return tuple(round(a * f + (1 - a) * b) for f, b in zip(fg, bg))

def tokens():
    out = {"light": {}, "dark": {}}
    for name, lo, dk, la, da in PAT.findall(SRC.read_text()):
        out["light"][name] = (rgb(int(lo, 16)), float(la or 1)); out["dark"][name] = (rgb(int(dk, 16)), float(da or 1))
    return out

def main() -> int:
    t = tokens(); bad = 0
    for mode, tk in t.items():
        flat = lambda n, base=None: tk[n][0] if tk[n][1] == 1 else over(tk[n][0], tk[n][1], base)
        win = flat("window"); ctl = flat("control", win); hov = flat("controlHover", win)
        pairs = [("ink on window", "ink", win, 4.5), ("ink2 on window", "ink2", win, 4.5), ("ink2 on window2", "ink2", flat("window2"), 4.5),
                 ("ink2 on sidebar", "ink2", flat("sidebar"), 4.5), ("ink2 on control", "ink2", ctl, 4.5), ("ink on control", "ink", ctl, 4.5),
                 ("ink on control hover", "ink", hov, 4.5), ("ink on accentSoft", "ink", flat("accentSoft"), 4.5),
                 ("accentInk on accentSoft (selected choice)", "accentInk", flat("accentSoft"), 4.5), ("ink2 on well", "ink2", flat("well"), 4.5),
                 ("ink2 on control over card", "ink2", over(tk["control"][0], tk["control"][1], flat("window2")), 4.5),
                 ("accent ring on window (non-text)", "accent", win, 3.0), ("accent text on window", "accent", win, 4.5), ("slip mark on window (non-text)", "slip", win, 3.0), ("slip mark on window2 (non-text)", "slip", flat("window2"), 3.0), ("ink on slipSoft", "ink", flat("slipSoft"), 4.5), ("onAccent on accent (primary button)", "onAccent", flat("accent"), 4.5),
                 ("ink on float (popups)", "ink", flat("float"), 4.5), ("ink2 on float (popups)", "ink2", flat("float"), 4.5),
                 ("ink on control over float (popup secondary button)", "ink", over(tk["control"][0], tk["control"][1], flat("float")), 4.5),
                 ("slipInk text on float (off-task timer)", "slipInk", flat("float"), 4.5), ("slipInk text on window", "slipInk", win, 4.5),
                 ("slip mark on float (non-text)", "slip", flat("float"), 3.0)]
        for label, fg, bg, need in pairs:
            r = ratio(tk[fg][0], bg); ok = r >= need; bad += not ok
            print(f"{mode:5} {'ok ' if ok else 'LOW'} {r:5.2f} (need {need}) {label}")
    # The notch is black in both appearances and has its own fixed colors (Tokens.Notch).
    src = SRC.read_text(); notch = {}
    for name, r, g, b in re.findall(r"static let (\w+) = Color\(red: ([\d.]+), green: ([\d.]+), blue: ([\d.]+)\)", src.split("enum Notch")[1].split("}")[0]):
        notch[name] = tuple(round(float(v) * 255) for v in (r, g, b))
    for label, fg, bg, need in [("notch ink on black", notch["ink"], (0, 0, 0), 4.5), ("notch ink2 on black", notch["ink2"], (0, 0, 0), 4.5),
                                ("notch accent on black (non-text)", notch["accent"], (0, 0, 0), 3.0), ("notch onAccent on accent", notch["onAccent"], notch["accent"], 4.5), ("notch slip text on black", notch["slip"], (0, 0, 0), 4.5)]:
        r = ratio(fg, bg); ok = r >= need; bad += not ok
        print(f"notch {'ok ' if ok else 'LOW'} {r:5.2f} (need {need}) {label}")
    print("all pairs pass" if not bad else f"{bad} pair(s) below target")
    return 1 if bad else 0

if __name__ == "__main__": sys.exit(main())
