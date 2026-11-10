# Draws the UI's moving halftone dots as one picture (Tag Rivals, steady-60-FPS work, 2026-11-09).
# One 8x8-dot tile of the wave (the wave repeats every DOT_CELLS dots, so tiles fit together) for each of FRAMES steps
# through the wave, laid out COLS across. White dots on clear; the game tints them and fades them.
# Same numbers as Config.Ui: DOT_CELLS 8, DOT_MIN 0.08, DOT_MAX 0.5. CELL is pixels per dot spacing in the picture.
import math
import sys
from PIL import Image, ImageDraw

CELLS, DOT_MIN, DOT_MAX = 8, 0.08, 0.5
FRAMES, COLS, CELL, SS = 32, 8, 14, 8  # SS: drawn this many times bigger, then shrunk (smooth edges)

tile = CELLS * CELL
rows = math.ceil(FRAMES / COLS)
big = Image.new("L", (COLS * tile * SS, rows * tile * SS), 0)
draw = ImageDraw.Draw(big)
for k in range(FRAMES):
    phase = k / FRAMES
    ox, oy = (k % COLS) * tile * SS, (k // COLS) * tile * SS
    for j in range(CELLS):
        for i in range(CELLS):
            wave = 0.5 + 0.5 * math.cos(2 * math.pi * ((i + j) / CELLS - phase))
            r = (DOT_MIN + (DOT_MAX - DOT_MIN) * wave) * CELL * SS
            cx, cy = ox + (i + 0.5) * CELL * SS, oy + (j + 0.5) * CELL * SS
            draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
alpha = big.resize((COLS * tile, rows * tile), Image.LANCZOS)
out = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
out.putalpha(alpha)
out.save(sys.argv[1])
print(out.size)
