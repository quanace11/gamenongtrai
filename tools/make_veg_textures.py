#!/usr/bin/env python3
"""Build the vegetation textures in assets/textures/veg/ (numpy + Pillow).

Usage: python3 tools/make_veg_textures.py [bamboo_twig.png]

- banana_leaf.png: drawn here (CC0). A banana blade 256 x 512 (across x
  along, petiole at the top): pale midrib, lateral veins at ~65 degrees, a
  yellow-brown dry margin, and tears that run from the edge along the veins
  toward the midrib (alpha = 0 in the tears).
- bamboo_spray.png: built from evolveduk's CC-BY 4.0 bamboo twig texture
  (Tree_1Mat_baseColor.png, see assets/CREDITS.md and tools/fetch_assets.py):
  the diagonal twig is turned upright, cropped, and a mirrored copy is laid
  under it for a denser spray. Skipped if the twig file is not given.
"""
import os, sys
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'textures', 'veg')


def banana(path, w=256, h=512, seed=11):
    rng = np.random.default_rng(seed)
    v = (np.arange(h) + 0.5)[:, None] / h          # along, 0 = petiole
    u = (np.arange(w) + 0.5)[None, :] / w - 0.5    # across, -0.5..0.5
    au = np.abs(u)
    # oblong blade: narrow petiole end, long parallel sides, rounded tip
    half = 0.47 * np.clip(v / 0.16, 0, 1) ** 0.55 * np.sqrt(np.clip((1.0 - v) / 0.14, 0, 1))
    inside = au < half
    rel = au / np.maximum(half, 1e-3)              # 0 midrib .. 1 margin
    # lateral veins run from the midrib outwards and toward the tip
    phase = (v - au * 0.42) * 150.0
    vein = 0.5 + 0.5 * np.cos(phase * 2 * np.pi / 1.0 * 0.5)
    col = np.zeros((h, w, 3))
    base = np.array([0.20, 0.42, 0.09])
    light = np.array([0.36, 0.58, 0.16])
    col[:] = base + (light - base) * (0.35 + 0.4 * rel[..., None] ** 0.7)
    col *= (0.93 + 0.07 * vein[..., None])
    # slow blotches
    blot = Image.fromarray(np.uint8(rng.random((16, 8)) * 255)).resize((w, h), Image.BICUBIC)
    blot = np.asarray(blot) / 255.0
    col *= (0.9 + 0.18 * blot[..., None])
    # midrib
    mid = np.clip(1.0 - au / (0.022 * (1.0 - 0.6 * v)), 0, 1)
    col = col * (1 - mid[..., None]) + np.array([0.70, 0.74, 0.42]) * mid[..., None]
    # dry, yellow-brown margin and tip
    dry = np.clip((rel - 0.9) / 0.1, 0, 1) * (0.4 + 0.6 * blot) + np.clip((v - 0.9) / 0.1, 0, 1)
    dry = np.clip(dry, 0, 1)
    col = col * (1 - dry[..., None]) + np.array([0.52, 0.42, 0.20]) * dry[..., None]
    alpha = inside.astype(np.float32)
    # tears along the veins, from the margin inwards
    for _ in range(30):
        v0 = rng.uniform(0.1, 0.95)
        side = rng.choice([-1, 1])
        depth = rng.uniform(0.25, 0.97)
        width = rng.uniform(0.0012, 0.0032)
        # a tear follows v - au*0.42 = const
        c = v0
        line = np.abs((v - au * 0.42) - c)
        tear = (line < width) & (np.sign(u) == side) & (rel > 1.0 - depth) & (au > 0.03)
        alpha[tear] = 0.0
        # dry brown lips along the tear
        lip = (line < width * 3.0) & (np.sign(u) == side) & (rel > 1.0 - depth) & inside
        col[lip] = col[lip] * 0.75 + np.array([0.45, 0.40, 0.20]) * 0.25
    img = np.concatenate([np.clip(col, 0, 1) * 255, alpha[..., None] * 255], axis=2)
    # bleed the colour into transparent texels so mipmaps keep the edge colour
    rgb = img[..., :3]
    avg = rgb[alpha > 0.5].mean(axis=0)
    rgb[alpha < 0.5] = avg
    Image.fromarray(np.uint8(img), 'RGBA').save(path, optimize=True)
    print('wrote', path)


def spray(src, path):
    im = Image.open(src).convert('RGBA')
    W = im.size[0]
    big = Image.new('RGBA', (W * 2, W * 2), (0, 0, 0, 0))
    big.paste(im, (W // 2, W // 2))
    rot = big.rotate(-45, resample=Image.BICUBIC, center=(W, W))
    a = np.array(rot)[:, :, 3]
    ys, xs = np.nonzero(a > 16)
    cx = int(np.argmax((a > 128).sum(axis=0)))  # the twig's column
    y0, y1 = ys.min(), ys.max()
    half = int((y1 - y0) * 0.27)
    crop = rot.crop((cx - half, y0, cx + half, y1)).resize((512, 1024), Image.LANCZOS)
    c2 = crop.transpose(Image.FLIP_LEFT_RIGHT).resize((440, 880), Image.LANCZOS)
    dense = Image.new('RGBA', (512, 1024), (0, 0, 0, 0))
    dense.alpha_composite(c2, (36, 150))
    dense.alpha_composite(crop, (0, 0))
    arr = np.array(dense).astype(np.float32)
    alpha = arr[:, :, 3:4] / 255.0
    rgb = arr[:, :, :3]
    avg = (rgb * alpha).sum(axis=(0, 1)) / max(alpha.sum(), 1.0)
    fill = Image.fromarray(np.uint8(np.clip(rgb * alpha + avg * (1 - alpha), 0, 255)))
    blur = np.array(fill.resize((32, 64), Image.BILINEAR).resize((512, 1024), Image.BILINEAR)).astype(np.float32)
    rgb2 = rgb * (alpha > 0.02) + blur * (alpha <= 0.02)
    res = np.concatenate([rgb2, arr[:, :, 3:4]], axis=2)
    Image.fromarray(np.uint8(np.clip(res, 0, 255)), 'RGBA').save(path, optimize=True)
    print('wrote', path)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    banana(os.path.join(OUT, 'banana_leaf.png'))
    if len(sys.argv) > 1:
        spray(sys.argv[1], os.path.join(OUT, 'bamboo_spray.png'))
