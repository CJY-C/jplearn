#!/usr/bin/env python3
"""Create the geometric app icon using only the Python standard library."""
import json
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "App/Assets.xcassets"


def rounded_rect(x, y, left, top, right, bottom, radius):
    cx = min(max(x, left + radius), right - radius)
    cy = min(max(y, top + radius), bottom - radius)
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2


def pixel(x, y):
    t = (x + y) / 2048
    color = (round(241 - 12 * t), round(248 - 4 * t), round(244 + 1 * t))
    if rounded_rect(x, y, 221, 167, 815, 883, 85):
        color = (211, 229, 221)
    if rounded_rect(x, y, 205, 145, 799, 857, 85):
        color = (255, 255, 251)
    for bounds, fill in [((312, 573, 398, 747, 27), (94, 161, 142)),
                         ((458, 435, 544, 747, 27), (57, 135, 119)),
                         ((604, 297, 690, 747, 27), (30, 104, 93))]:
        if rounded_rect(x, y, *bounds):
            color = fill
    return bytes(color)


def chunk(kind, data):
    return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def main():
    app_icon = ASSETS / "AppIcon.appiconset"
    app_icon.mkdir(parents=True, exist_ok=True)
    raw = b"".join(b"\0" + b"".join(pixel(x, y) for x in range(1024)) for y in range(1024))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack("!2I5B", 1024, 1024, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    (app_icon / "AppIcon.png").write_bytes(png)
    (app_icon / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    accent = ASSETS / "AccentColor.colorset"
    accent.mkdir(exist_ok=True)
    (accent / "Contents.json").write_text(json.dumps({
        "colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {
            "red": "0.118", "green": "0.408", "blue": "0.365", "alpha": "1.000"}}}],
        "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    (ASSETS / "Contents.json").write_text('{"info":{"author":"xcode","version":1}}\n')
    print("Generated AppIcon and AccentColor.")


if __name__ == "__main__":
    main()
