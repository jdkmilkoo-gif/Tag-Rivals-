# Makes the neon UI pictures for Tag Rivals (owner 2026-11-10: "Add these", the neon "MAP SHRINKING IN 1" banner and the
# kill-feed rows from the owner's pictures). Run: python make_neon_ui.py  (writes the PNGs next to this file).
#   ShrinkBanner.png   the shrink warning's plate: dark red glass, a neon red double edge with a glow, slanted ends
#                      (drawn as a 9-slice: the middle stretches, the ends keep their shape)
#   NeonChevronRed.png one fat chevron pointing right, neon red with a hot pink edge and a glow (the banner's arrows)
#   NeonChevronAmber.png the same in amber (the bridges' signs in the background)
#   ChevronWhite.png   a white chevron with a soft glow, for tinting (the arrows on the red strip)
#   NeonRow.png        a feed row's frame: a rounded white neon edge with a glow, for tinting (9-slice)
#   NeonBolt.png       a little lightning bolt, yellow to orange, with a glow
#   SheenBand.png      a soft white band that sweeps across the banner
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))


def save(img, name):
    img.save(os.path.join(HERE, name))
    print(name, img.size)


def glow_layer(mask, radius, color, strength=1.0):
    """A coloured glow from a white-on-black mask (L image)."""
    blurred = mask.filter(ImageFilter.GaussianBlur(radius))
    a = np.asarray(blurred, dtype=np.float32) / 255.0
    a = np.clip(a * strength, 0, 1)
    out = np.zeros((mask.height, mask.width, 4), dtype=np.float32)
    out[..., 0] = color[0]
    out[..., 1] = color[1]
    out[..., 2] = color[2]
    out[..., 3] = a * 255
    return out


def over(dst, src):
    """Alpha-composite float RGBA arrays (src over dst)."""
    sa = src[..., 3:4] / 255.0
    da = dst[..., 3:4] / 255.0
    oa = sa + da * (1 - sa)
    rgb = (src[..., :3] * sa + dst[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-6)
    return np.concatenate([rgb, oa * 255], axis=-1)


def solid(mask, color, alpha=1.0):
    a = np.asarray(mask, dtype=np.float32) / 255.0 * alpha
    out = np.zeros((mask.height, mask.width, 4), dtype=np.float32)
    out[..., :3] = color
    out[..., 3] = a * 255
    return out


def to_img(arr):
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def poly_mask(size, points, width=0, ss=4):
    """Anti-aliased polygon (filled, or an outline `width` px wide) via supersampling."""
    w, h = size
    big = Image.new("L", (w * ss, h * ss), 0)
    d = ImageDraw.Draw(big)
    pts = [(x * ss, y * ss) for x, y in points]
    if width > 0:
        d.line(pts + [pts[0]], fill=255, width=int(width * ss), joint="curve")
    else:
        d.polygon(pts, fill=255)
    return big.resize((w, h), Image.LANCZOS)


# ------------------------------------------------------------------ the banner plate
def banner():
    W, H = 1024, 200
    PAD = 34  # room for the glow
    SL = 26  # how far the ends slant
    x0, x1, y0, y1 = PAD, W - PAD, PAD, H - PAD
    # a parallelogram leaning right (like the italic words), with a little notch cut at the top-right and bottom-left
    outer = [(x0 + SL, y0), (x1 - 14, y0), (x1, y0 + 14), (x1 - SL, y1), (x0 + 14, y1), (x0, y1 - 14)]
    inset = 7
    inner = [
        (x0 + SL + inset, y0 + inset),
        (x1 - 14 - inset * 0.6, y0 + inset),
        (x1 - inset * 1.3, y0 + 14 + inset * 0.4),
        (x1 - SL - inset, y1 - inset),
        (x0 + 14 + inset * 0.6, y1 - inset),
        (x0 + inset * 1.3, y1 - 14 - inset * 0.4),
    ]
    fill = poly_mask((W, H), outer)
    # the glass: deep red at the top to near black, a little see-through
    yy = np.linspace(0, 1, H)[:, None]
    body = np.zeros((H, W, 4), dtype=np.float32)
    top = np.array([92, 8, 34], dtype=np.float32)
    bottom = np.array([24, 2, 12], dtype=np.float32)
    col = top * (1 - yy[..., None]) + bottom * yy[..., None]
    body[..., :3] = np.broadcast_to(col, (H, W, 3))
    body[..., 3] = np.asarray(fill, dtype=np.float32) * 0.86
    # a red glow just inside the edge
    edge = poly_mask((W, H), outer, width=5)
    inside = Image.fromarray(
        (np.asarray(edge.filter(ImageFilter.GaussianBlur(10)), dtype=np.float32) * (np.asarray(fill) / 255.0)).astype(
            np.uint8
        )
    )
    img = np.zeros((H, W, 4), dtype=np.float32)
    img = over(img, glow_layer(edge, 16, (255, 30, 70), 1.6))  # the glow outside
    img = over(img, body)
    img = over(img, glow_layer(inside, 2, (255, 40, 80), 1.2))
    # the double edge: a bright outer line and a thin inner one
    img = over(img, solid(poly_mask((W, H), outer, width=5), (255, 52, 92)))
    img = over(img, solid(poly_mask((W, H), outer, width=1.6), (255, 205, 215)))
    img = over(img, solid(poly_mask((W, H), inner, width=2), (255, 70, 110), 0.85))
    save(to_img(img), "ShrinkBanner.png")


# ------------------------------------------------------------------ chevrons
def chevron_points(w, h, pad, thick):
    # a fat ">" : two slanted arms meeting at a point on the right
    left = pad
    right = w - pad
    top = pad
    bottom = h - pad
    mid = h / 2
    return [
        (left, top),
        (left + thick, top),
        (right, mid),
        (left + thick, bottom),
        (left, bottom),
        (right - thick, mid),
    ]


def chevron(name, fill_top, fill_bottom, edge, hot, glow):
    W, H = 128, 160
    PAD = 26
    pts = chevron_points(W, H, PAD, 30)
    mask = poly_mask((W, H), pts)
    yy = np.linspace(0, 1, H)[:, None, None]
    col = np.array(fill_top, np.float32) * (1 - yy) + np.array(fill_bottom, np.float32) * yy
    body = np.zeros((H, W, 4), np.float32)
    body[..., :3] = np.broadcast_to(col, (H, W, 3))
    body[..., 3] = np.asarray(mask, np.float32)
    img = np.zeros((H, W, 4), np.float32)
    img = over(img, glow_layer(mask, 11, glow, 1.5))
    img = over(img, body)
    img = over(img, solid(poly_mask((W, H), pts, width=4), edge))
    img = over(img, solid(poly_mask((W, H), pts, width=1.4), hot, 0.9))
    save(to_img(img), name)


def chevron_white():
    W, H = 128, 160
    pts = chevron_points(W, H, 22, 30)
    mask = poly_mask((W, H), pts)
    img = np.zeros((H, W, 4), np.float32)
    img = over(img, glow_layer(mask, 9, (255, 255, 255), 1.0))
    img = over(img, solid(mask, (255, 255, 255)))
    save(to_img(img), "ChevronWhite.png")


# ------------------------------------------------------------------ the feed row's frame
def row():
    W, H = 256, 96
    PAD = 18
    big = 4
    m = Image.new("L", (W * big, H * big), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle(
        (PAD * big, PAD * big, (W - PAD) * big, (H - PAD) * big), radius=12 * big, outline=255, width=3 * big
    )
    edge = m.resize((W, H), Image.LANCZOS)
    thin = Image.new("L", (W * big, H * big), 0)
    ImageDraw.Draw(thin).rounded_rectangle(
        (PAD * big + 1 * big, PAD * big + 1 * big, (W - PAD) * big - 1 * big, (H - PAD) * big - 1 * big),
        radius=11 * big,
        outline=255,
        width=1 * big,
    )
    thin = thin.resize((W, H), Image.LANCZOS)
    img = np.zeros((H, W, 4), np.float32)
    img = over(img, glow_layer(edge, 7, (255, 255, 255), 1.3))
    img = over(img, solid(edge, (235, 235, 235)))
    img = over(img, solid(thin, (255, 255, 255)))
    save(to_img(img), "NeonRow.png")


# ------------------------------------------------------------------ the lightning bolt
def bolt():
    W, H = 96, 128
    pts = [(58, 14), (24, 70), (46, 70), (34, 114), (74, 52), (51, 52), (66, 14)]
    mask = poly_mask((W, H), pts)
    yy = np.linspace(0, 1, H)[:, None, None]
    col = np.array([255, 236, 90], np.float32) * (1 - yy) + np.array([255, 120, 20], np.float32) * yy
    body = np.zeros((H, W, 4), np.float32)
    body[..., :3] = np.broadcast_to(col, (H, W, 3))
    body[..., 3] = np.asarray(mask, np.float32)
    img = np.zeros((H, W, 4), np.float32)
    img = over(img, glow_layer(mask, 8, (255, 140, 30), 1.4))
    img = over(img, body)
    img = over(img, solid(poly_mask((W, H), pts, width=2.5), (120, 30, 0), 0.8))
    save(to_img(img), "NeonBolt.png")


# ------------------------------------------------------------------ the sheen
def sheen():
    W, H = 256, 64
    xx = np.linspace(-1, 1, W)[None, :]
    a = np.exp(-(xx / 0.22) ** 2) * np.ones((H, 1))
    img = np.zeros((H, W, 4), np.float32)
    img[..., :3] = 255
    img[..., 3] = a * 255
    save(to_img(img), "SheenBand.png")


if __name__ == "__main__":
    banner()
    chevron("NeonChevronRed.png", (255, 70, 105), (214, 10, 52), (255, 40, 85), (255, 215, 225), (255, 20, 70))
    chevron("NeonChevronAmber.png", (255, 226, 92), (255, 140, 20), (255, 176, 40), (255, 250, 210), (255, 150, 30))
    chevron_white()
    row()
    bolt()
    sheen()
