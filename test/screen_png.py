"""
screen_png.py - turn recorded norns screen calls into PNGs (128x64, 16 grey levels).

    lua5.3 test/render_screens.lua > /tmp/frames.txt
    python3 test/screen_png.py /tmp/frames.txt screens/quick.png      (needs Pillow; mkdir -p screens first)

Input: blocks starting "FRAME<tab>name", then one screen call per line, tab separated
(level, rect, fill, move, line, stroke, text, text_right). Output: one sheet with every
frame at 4x plus a label.

Rects are pixel-exact (aa off). Lines are drawn with Bresenham, which is close to but not
the same as the Cairo stroker norns uses: measured 2026-11-23 against Weft's Cairo 1.16
replay, rects matched 0 px and lines differed by 120-210 px per frame. Text uses a
hand-made 3x5 font that is close to norns font 1 but not identical. For exact pixels use
Weft's screens.py with test/screens.lua (see test/README.md).
"""
import sys
from PIL import Image, ImageDraw, ImageFont

W, H = 128, 64

FONT = {
    '0': ["###", "#.#", "#.#", "#.#", "###"], '1': [".#.", "##.", ".#.", ".#.", "###"],
    '2': ["###", "..#", "###", "#..", "###"], '3': ["###", "..#", ".##", "..#", "###"],
    '4': ["#.#", "#.#", "###", "..#", "..#"], '5': ["###", "#..", "###", "..#", "###"],
    '6': ["###", "#..", "###", "#.#", "###"], '7': ["###", "..#", "..#", ".#.", ".#."],
    '8': ["###", "#.#", "###", "#.#", "###"], '9': ["###", "#.#", "###", "..#", "###"],
    '.': [".", ".", ".", ".", "#"], '%': ["#.#", "..#", ".#.", "#..", "#.#"],
    '+': ["...", ".#.", "###", ".#.", "..."], '-': ["...", "...", "###", "...", "..."],
    '/': ["..#", "..#", ".#.", "#..", "#.."], ' ': ["..", "..", "..", "..", ".."],
    'G': [".###", "#...", "#.##", "#..#", ".###"], 'M': ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
    'a': ["...", ".##", "#.#", "#.#", ".##"], 'b': ["#..", "##.", "#.#", "#.#", "##."],
    'c': ["...", ".##", "#..", "#..", ".##"], 'd': ["..#", ".##", "#.#", "#.#", ".##"],
    'e': ["...", ".#.", "###", "#..", ".##"], 'i': ["#", ".", "#", "#", "#"],
    'l': ["#", "#", "#", "#", "#"], 'n': ["...", "##.", "#.#", "#.#", "#.#"],
    'o': ["...", ".#.", "#.#", "#.#", ".#."], 'p': ["...", "##.", "#.#", "##.", "#.."],
    'r': ["...", "#.#", "##.", "#..", "#.."], 's': ["...", ".##", ".#.", "..#", "##."],
    't': [".#.", "###", ".#.", ".#.", "..#"], 'u': ["...", "#.#", "#.#", "#.#", ".##"],
}
UNKNOWN = ["###", "#.#", "#.#", "#.#", "###"]


class Screen:
    def __init__(self):
        self.buf = [[0] * W for _ in range(H)]
        self.lv = 15

    def pixel(self, x, y):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < W and 0 <= y < H:
            self.buf[y][x] = self.lv

    def rect(self, x, y, w, h):
        for j in range(int(h)):
            for i in range(int(w)):
                self.pixel(x + i, y + j)

    def line(self, x0, y0, x1, y1):
        x0, y0, x1, y1 = (int(round(v)) for v in (x0, y0, x1, y1))
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.pixel(x0, y0)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy; x0 += sx
            if e2 <= dx:
                err += dx; y0 += sy

    def glyph(self, ch):
        return FONT.get(ch, UNKNOWN)

    def text(self, s, x, top):
        for ch in s:
            g = self.glyph(ch)
            for j, row in enumerate(g):
                for i, c in enumerate(row):
                    if c == '#':
                        self.pixel(x + i, top + j)
            x += len(g[0]) + 1

    def text_width(self, s):
        return sum(len(self.glyph(c)[0]) + 1 for c in s) - 1

    def image(self, scale):
        img = Image.new("L", (W, H))
        img.putdata([round(v / 15 * 255) for row in self.buf for v in row])
        return img.resize((W * scale, H * scale), Image.NEAREST)


def replay(path):
    frames, cur = [], None
    for line in open(path):
        p = line.rstrip("\n").split("\t")
        if p[0] == "FRAME":
            cur = {"name": p[1], "s": Screen(), "path": [], "pos": (0, 0), "lines": []}
            frames.append(cur)
            continue
        if cur is None:
            continue
        s, op, a = cur["s"], p[0], p[1:]
        if op == "level":
            s.lv = int(float(a[0]))
        elif op == "rect":
            cur["path"].append(tuple(float(v) for v in a[:4]))
        elif op == "fill":
            for x, y, w, h in cur["path"]:
                s.rect(int(x), int(y), w, h)
            cur["path"] = []
        elif op == "move":
            cur["pos"] = (float(a[0]), float(a[1]))
        elif op == "line":
            cur["lines"].append((cur["pos"], (float(a[0]), float(a[1]))))
            cur["pos"] = (float(a[0]), float(a[1]))
        elif op == "stroke":
            for (x0, y0), (x1, y1) in cur["lines"]:
                s.line(x0, y0, x1, y1)
            cur["lines"] = []
        elif op == "text":   # norns: move() sets the baseline
            s.text(a[0], int(cur["pos"][0]), int(cur["pos"][1]) - 5)
        elif op == "text_right":
            s.text(a[0], int(cur["pos"][0]) - s.text_width(a[0]), int(cur["pos"][1]) - 5)
    return frames


def sheet(frames, out, scale=4, cols=2):
    pad, label = 28, 26
    fw, fh = W * scale, H * scale
    rows = (len(frames) + cols - 1) // cols
    img = Image.new("L", (cols * fw + (cols + 1) * pad, rows * (fh + label + pad) + pad), 196)
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("Inter-Regular.otf", 15)
    except OSError:
        font = ImageFont.load_default()
    for i, f in enumerate(frames):
        c, r = i % cols, i // cols
        x, y = pad + c * (fw + pad), pad + r * (fh + label + pad)
        d.text((x, y), f["name"], fill=60, font=font)
        img.paste(f["s"].image(scale), (x, y + label))
    img.save(out)


if __name__ == "__main__":
    frames = replay(sys.argv[1])
    sheet(frames, sys.argv[2] if len(sys.argv) > 2 else "screens.png")
    print(f"{len(frames)} frames -> {sys.argv[2] if len(sys.argv) > 2 else 'screens.png'}")
