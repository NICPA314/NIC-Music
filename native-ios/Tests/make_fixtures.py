"""Generate original test tones and solid artwork; no user music is bundled."""
from pathlib import Path
import struct
import subprocess
import sys
import zlib

folder = Path(__file__).parent / "Fixtures"
folder.mkdir(exist_ok=True)
ffmpeg = sys.argv[1] if len(sys.argv) > 1 else "ffmpeg"

def png(path, rgb):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 64, 64, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress((b"\0" + bytes(rgb) * 64) * 64)) + chunk(b"IEND", b""))

png(folder / "cover.png", (30, 90, 220))
png(folder / "embedded.png", (220, 50, 70))

def atom(kind, body):
    return struct.pack(">I", len(body) + 8) + kind + body

def add_label(data):
    result = bytearray()
    cursor = 0
    while cursor < len(data):
        size, kind = struct.unpack(">I4s", data[cursor:cursor + 8])
        body = data[cursor + 8:cursor + size]
        if kind in [b"moov", b"udta"]:
            body = add_label(body)
        elif kind == b"meta":
            body = body[:4] + add_label(body[4:])
        elif kind == b"ilst":
            body += atom(b"----", atom(b"mean", b"\0" * 4 + b"com.apple.iTunes") + atom(b"name", b"\0" * 4 + b"LABEL") + atom(b"data", struct.pack(">II", 1, 0) + b"Fixture Records"))
        result += atom(kind, body)
        cursor += size
    return bytes(result)

for index, (filename, title) in enumerate([("01. Wrong Filename", "Metadata Title"), ("02. Second", "Second Track"), ("03. Third", "Third Track")], 1):
    target = folder / (filename + ".m4a")
    args = [ffmpeg, "-v", "error", "-y", "-f", "lavfi", "-i", f"sine=frequency={330 + index * 110}:sample_rate=48000:duration=6"]
    if index == 1:
        args += ["-i", str(folder / "embedded.png"), "-map", "0:a", "-map", "1:v", "-c:v", "png", "-disposition:v", "attached_pic"]
    args += ["-c:a", "alac", "-sample_fmt", "s32"]
    for key, value in {"title": title, "artist": "Test Artist", "album_artist": "Test Artist", "album": "Test Album", "date": "2024-01-02", "track": f"{index}/3", "disc": "1/1", "copyright": "2024 Fixture Records", "genre": "Test", "composer": "Fixture Composer"}.items():
        args += ["-metadata", f"{key}={value}"]
    subprocess.run(args + [str(target)], check=True)
    target.write_bytes(add_label(target.read_bytes()))
print("Generated three ALAC tones and two solid-color images.")
