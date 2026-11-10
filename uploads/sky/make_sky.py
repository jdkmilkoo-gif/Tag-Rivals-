# Makes Tag Rivals' neon dusk sky (owner 2026-11-10: "like the back ground too", the purple sunset sky over a sea of
# clouds in the owner's pictures). Six 1024x1024 faces of a cube, worked out from the direction each pixel looks in, so
# the faces meet without seams:
#   * a deep indigo top fading through violet and magenta to a hot pink horizon, warm peach where the sun has set;
#   * stars in the upper sky;
#   * thin pink streaks of high cloud above the horizon;
#   * a thick sea of clouds below, lit pink and lavender on top with deep purple shadows (the arena floats over it).
# Roblox's faces (checked in Studio with labelled test faces, 2026-11-10): Ft looks along -Z, Bk +Z, Lf +X, Rt -X, Up,
# Dn. In each picture u runs left to right and v top to bottom, both -1 to 1.
# Run: python make_sky.py  (writes Sky_<face>.png next to this file and a preview strip).
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
N = int(os.environ.get("SKY_SIZE", "1024"))
rng = np.random.default_rng(7)

FACES = {
    "Ft": lambda u, v: (u, -v, -np.ones_like(u)),
    "Lf": lambda u, v: (np.ones_like(u), -v, u),
    "Bk": lambda u, v: (-u, -v, np.ones_like(u)),
    "Rt": lambda u, v: (-np.ones_like(u), -v, -u),
    "Up": lambda u, v: (-v, np.ones_like(u), -u),
    "Dn": lambda u, v: (v, -np.ones_like(u), -u),
}

# ------------------------------------------------------------------ noise
LATTICE = 512
grid = rng.random((LATTICE, LATTICE)).astype(np.float32)


def value_noise(x, y):
    xi = np.floor(x).astype(np.int64)
    yi = np.floor(y).astype(np.int64)
    fx = x - xi
    fy = y - yi
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    x0 = xi % LATTICE
    y0 = yi % LATTICE
    x1 = (x0 + 1) % LATTICE
    y1 = (y0 + 1) % LATTICE
    a = grid[y0, x0]
    b = grid[y0, x1]
    c = grid[y1, x0]
    d = grid[y1, x1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(x, y, octaves=6, lacunarity=2.03, gain=0.5):
    total = np.zeros_like(x)
    amp = 0.5
    norm = 0.0
    for i in range(octaves):
        # a different offset and a slight turn each octave hides the lattice
        ang = 0.6 * i
        ca, sa = np.cos(ang), np.sin(ang)
        xr = x * ca - y * sa + 17.3 * i
        yr = x * sa + y * ca - 9.1 * i
        total += amp * value_noise(xr, yr)
        norm += amp
        x = x * lacunarity
        y = y * lacunarity
        amp *= gain
    return total / norm


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    t = np.asarray(t)[..., None]
    return a * (1 - t) + b * t


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0


# ------------------------------------------------------------------ colours
ZENITH = hexc("120E38")
HIGH = hexc("2A1C66")
MID = hexc("5A2E9E")
LOW = hexc("A93FA8")
HORIZON = hexc("FF6FA6")
SUNSET = hexc("FFB48A")
CLOUD_LIT = hexc("FFD2F2")
CLOUD_WARM = hexc("FFC6A8")
CLOUD_MID = hexc("B07AD8")
CLOUD_SHADOW = hexc("553694")
CLOUD_DEEP = hexc("2A1C5A")
WISP = hexc("FF8EC6")
WISP_COOL = hexc("B27BFF")

SUN = np.array([0.0, 0.04, -1.0])  # the sun has just set towards -Z (behind Ft), a warm glow there
SUN = SUN / np.linalg.norm(SUN)


def sky_color(dx, dy, dz):
    el = dy  # -1..1 (sine of the elevation)
    # the gradient by height
    c = mix(HORIZON, LOW, smoothstep(0.0, 0.16, el))
    c = mix(c, MID, smoothstep(0.12, 0.38, el))
    c = mix(c, HIGH, smoothstep(0.35, 0.7, el))
    c = mix(c, ZENITH, smoothstep(0.65, 1.0, el))
    # the warm glow where the sun set
    toward = dx * SUN[0] + dy * SUN[1] + dz * SUN[2]
    glow = np.clip(toward, 0, 1) ** 6 * np.exp(-np.maximum(el, 0) * 5.5)
    c = mix(c, SUNSET, np.clip(glow * 0.9, 0, 0.85))
    # a broad pink band round the whole horizon
    band = np.exp(-((el - 0.015) / 0.06) ** 2)
    c = mix(c, HORIZON * 1.05, band * 0.55)
    return c, toward


def stars(dx, dy, dz, u, v):
    # little points by a hash on the face's own pixels (too small to show the seams), only in the upper sky
    # drawn on a half-size grid and blown up, so each star is 2x2 pixels at full size (1 pixel vanishes in the game)
    half = (u.shape[0] // 2, u.shape[1] // 2)

    def big(a):
        return np.repeat(np.repeat(a, 2, axis=0), 2, axis=1)

    h = big(rng.random(half).astype(np.float32))
    bright = big(rng.random(half).astype(np.float32))
    fade = smoothstep(0.18, 0.6, dy)
    mask = (h > 0.9975) * fade
    tint = big(rng.random(half))
    col = np.stack(
        [
            np.where(tint < 0.2, 0.75, 1.0),
            np.where(tint > 0.85, 0.8, 1.0),
            np.ones_like(tint),
        ],
        -1,
    ).astype(np.float32)
    return mask * (0.4 + 0.6 * bright), col


def wisps(dx, dy, dz, toward):
    # long thin streaks of high cloud lying along the horizon (noise round the horizon's circle, so no seam, squashed
    # flat so the streaks run sideways)
    az = np.arctan2(dz, dx)
    el = dy
    r = 3.2
    cx, cz = np.cos(az) * r, np.sin(az) * r
    n = fbm(cx + el * 34.0 + 5.0, cz - el * 21.0 + 2.0, octaves=6)
    n2 = fbm(cx * 2.6 + el * 70.0, cz * 2.6 - el * 50.0, octaves=4)
    n = n * 0.75 + n2 * 0.35
    dens = smoothstep(0.55, 0.8, n)
    dens *= smoothstep(0.012, 0.05, el) * (1 - smoothstep(0.16, 0.42, el))
    warm = np.clip(toward, 0, 1) ** 2
    col = mix(WISP_COOL, WISP, 0.35 + 0.65 * warm)
    # their undersides glow a little brighter
    col = col * (1.0 + 0.25 * smoothstep(0.6, 0.85, n))[..., None]
    return dens * 0.85, col


def cloud_sea(dx, dy, dz, toward):
    # the sea of clouds below: a layer under the arena, seen in perspective
    down = np.maximum(-dy, 1e-3)
    t = 1.0 / down
    px = dx * t * 3.2
    pz = dz * t * 3.2
    big = fbm(px * 0.18 + 7.0, pz * 0.18 + 3.0, octaves=3)
    base = fbm(px + 40.0, pz - 25.0, octaves=7)
    n = base * 0.62 + big * 0.62 - 0.08
    # puffy: round the heaps' tops off
    dens = smoothstep(0.3, 0.52, n)
    # light from the sunset side: compare with the noise a step towards the sun
    sx, sz = SUN[0], SUN[2]
    step = 0.22
    nl = fbm(px + 40.0 - sx * step, pz - 25.0 - sz * step, octaves=6) * 0.62 + big * 0.62 - 0.08
    lit = np.clip(0.5 + (n - nl) * 6.0, 0, 1)
    height = smoothstep(0.32, 0.78, n)  # the tops of the heaps catch more light
    warm = np.clip(toward, 0, 1) ** 3
    top = mix(CLOUD_LIT, CLOUD_WARM, warm * 0.8)
    col = mix(CLOUD_SHADOW, CLOUD_MID, height)
    col = mix(col, top, np.clip(lit * 0.75 + height * 0.45, 0, 1) * height)
    # between the heaps: deep purple
    gap = mix(CLOUD_DEEP, CLOUD_SHADOW, 0.35)
    col = mix(gap, col, dens)
    # haze near the horizon, pink, so the sea melts into the sky
    haze = 1 - smoothstep(0.0, 0.2, down)
    col = mix(col, HORIZON * 0.92, haze * 0.8)
    return col


def face(name):
    s = (np.arange(N, dtype=np.float32) + 0.5) / N * 2 - 1
    u, v = np.meshgrid(s, s)
    dx, dy, dz = FACES[name](u, v)
    length = np.sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / length, dy / length, dz / length
    sky, toward = sky_color(dx, dy, dz)
    star, star_col = stars(dx, dy, dz, u, v)
    sky = sky + star[..., None] * star_col * 0.9
    wd, wc = wisps(dx, dy, dz, toward)
    sky = mix(sky, wc, wd)
    sea = cloud_sea(dx, dy, dz, toward)
    below = smoothstep(0.004, -0.02, dy)  # 1 under the horizon
    col = mix(sky, sea, below)
    # a little dither so the gradients don't band
    col = col + (rng.random(col.shape).astype(np.float32) - 0.5) / 255.0 * 1.5
    img = Image.fromarray((np.clip(col, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
    img.save(os.path.join(HERE, f"Sky_{name}.png"))
    print(name)
    return img


if __name__ == "__main__":
    imgs = {name: face(name) for name in FACES}
    # a preview: the four sides in a row, Up over Ft, Dn under it
    small = {k: v.resize((256, 256), Image.LANCZOS) for k, v in imgs.items()}
    strip = Image.new("RGB", (256 * 4, 256 * 3), (0, 0, 0))
    for i, k in enumerate(["Rt", "Ft", "Lf", "Bk"]):
        strip.paste(small[k], (256 * i, 256))
    strip.paste(small["Up"], (256, 0))
    strip.paste(small["Dn"], (256, 512))
    strip.save(os.path.join(HERE, "sky_preview.png"))
