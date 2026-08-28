#!/usr/bin/env python3
"""Generate 1-bit OLED frames from the Robine running concept sheet."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "robine-running-concept.png"
OUTPUT = ROOT / "include" / "robine_sprites.h"
WIDTH = 52
HEIGHT = 40
FRAME_BOXES = (
    (80, 315, 430, 668),
    (480, 280, 860, 668),
    (895, 325, 1335, 670),
    (1400, 335, 1730, 670),
)


def make_frame(source: Image.Image, box: tuple[int, int, int, int]) -> Image.Image:
    crop = source.crop(box).point(lambda pixel: 255 if pixel >= 145 else 0)
    crop.thumbnail((50, 38), Image.Resampling.LANCZOS)
    crop = crop.point(lambda pixel: 255 if pixel >= 105 else 0).convert("1")
    frame = Image.new("1", (WIDTH, HEIGHT), 0)
    frame.paste(crop, ((WIDTH - crop.width) // 2, HEIGHT - crop.height))
    return frame


def xbm_bytes(frame: Image.Image) -> list[int]:
    values = []
    for y in range(HEIGHT):
        for byte_x in range((WIDTH + 7) // 8):
            value = 0
            for bit in range(8):
                x = byte_x * 8 + bit
                if x < WIDTH and frame.getpixel((x, y)):
                    value |= 1 << bit
            values.append(value)
    return values


def format_frame(values: list[int]) -> str:
    rows = []
    for index in range(0, len(values), 14):
        chunk = ", ".join(f"0x{value:02x}" for value in values[index : index + 14])
        rows.append(f"    {chunk},")
    return "\n".join(rows)


def main() -> None:
    source = Image.open(SOURCE).convert("L")
    frames = [xbm_bytes(make_frame(source, box)) for box in FRAME_BOXES]
    body = ",\n  ".join("{\n" + format_frame(frame) + "\n  }" for frame in frames)
    OUTPUT.write_text(
        "#pragma once\n\n"
        "#include <Arduino.h>\n\n"
        f"constexpr uint8_t kRobineSpriteWidth = {WIDTH};\n"
        f"constexpr uint8_t kRobineSpriteHeight = {HEIGHT};\n"
        f"constexpr uint8_t kRobineFrameCount = {len(frames)};\n\n"
        f"static const uint8_t kRobineFrames[{len(frames)}]"
        f"[{len(frames[0])}] PROGMEM = {{\n  {body}\n}};\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
