#!/usr/bin/env python3
"""make-covers.py — generate the 12 deterministic cover images.

Hand-rolled minimal PNGs (8-bit RGB, solid fill + darker border) built with
nothing but the standard library, so the harness box needs no Pillow. The
bytes are fully deterministic for a given book id: same palette, same size,
same zlib level — parity checks may hash the objects.

Usage: make-covers.py [OUT_DIR]      (default: ./covers-out)
Writes OUT_DIR/1.png … OUT_DIR/12.png; deploy.sh uploads them to
s3://<assets-bucket>/covers/.
"""

import pathlib
import struct
import sys
import zlib

WIDTH, HEIGHT = 24, 32

# One fixed spine colour per book id — deliberately bookish, never random.
PALETTE = {
    1: (46, 110, 78),
    2: (140, 58, 58),
    3: (58, 76, 140),
    4: (120, 96, 48),
    5: (236, 240, 244),
    6: (96, 56, 100),
    7: (168, 128, 48),
    8: (52, 52, 52),
    9: (88, 108, 60),
    10: (188, 148, 100),
    11: (216, 160, 176),
    12: (32, 96, 96),
}


def _chunk(tag, data):
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def make_png(rgb):
    border = bytes(c // 2 for c in rgb)
    fill = bytes(rgb)
    rows = bytearray()
    for y in range(HEIGHT):
        rows += b"\x00"  # filter type 0 (None) per scanline
        for x in range(WIDTH):
            edge = x in (0, WIDTH - 1) or y in (0, HEIGHT - 1)
            rows += border if edge else fill
    ihdr = struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", zlib.compress(bytes(rows), 9))
        + _chunk(b"IEND", b"")
    )


def main():
    out_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "covers-out")
    out_dir.mkdir(parents=True, exist_ok=True)
    for book_id, rgb in sorted(PALETTE.items()):
        (out_dir / f"{book_id}.png").write_bytes(make_png(rgb))
    print(f"wrote {len(PALETTE)} covers to {out_dir}")


if __name__ == "__main__":
    main()
