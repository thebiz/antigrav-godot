# Erzeugt die Dschungel-Bildkarten: Baum-Atlas (aus 4 gerenderten Ansichten) und Unterholz-Atlas (prozedural gezeichnet)
import sys, math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

def dilate(im, n=12):
    # Farbe in die durchsichtigen Ränder ausdehnen, damit beim Verkleinern keine dunklen Säume entstehen
    a = np.asarray(im).astype(np.float32)
    rgb, al = a[..., :3], a[..., 3] > 8
    for _ in range(n):
        acc = np.zeros_like(rgb); cnt = np.zeros(al.shape, np.float32)
        for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
            m = np.roll(al, (dy, dx), (0, 1)); c = np.roll(rgb, (dy, dx), (0, 1))
            acc += c * m[..., None]; cnt += m
        grow = (~al) & (cnt > 0)
        rgb[grow] = acc[grow] / cnt[grow][:, None]
        al = al | grow
    out = np.concatenate([rgb, a[..., 3:4]], -1)
    return Image.fromarray(out.clip(0, 255).astype(np.uint8), 'RGBA')

def tree_atlas(src, dst):
    o = Image.new('RGBA', (2048, 768), (0, 0, 0, 0))
    for i in range(4):
        o.paste(Image.open(src % i).convert('RGBA'), (i * 512, 0))
    dilate(o).save(dst)

def leaf(d, x, y, ang, L, W, col):
    # spitzes Blatt als Vieleck
    pts = []
    for t in np.linspace(0, 1, 14):
        w = W * math.sin(math.pi * t) ** 0.8
        pts.append((t * L, w))
    pts += [(t * L, -w) for (t, w) in [(p[0] / L, p[1]) for p in reversed(pts)]]
    ca, sa = math.cos(ang), math.sin(ang)
    d.polygon([(x + px * ca - py * sa, y + px * sa + py * ca) for px, py in pts], fill=col)

def cell_fern(rnd, S):
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    for f in range(11):
        a0 = -math.pi / 2 + rnd.uniform(-1.25, 1.25)
        L = S * rnd.uniform(0.6, 0.85); bend = rnd.uniform(-0.9, 0.9)
        x, y = S / 2 + rnd.uniform(-8, 8), S * 0.98
        g = rnd.uniform(0.75, 1.15)
        for i in range(40):
            t = i / 40
            ang = a0 + bend * t * t
            nx, ny = x + math.cos(ang) * L / 40, y + math.sin(ang) * L / 40
            d.line([(x, y), (nx, ny)], fill=(40, 70, 25, 255), width=2)
            if i > 3:
                lw = S * 0.05 * (1 - t) ** 0.6 + 2
                c = (int(35 * g), int((95 + 70 * t) * g), int(30 * g), 255)
                for sd in (-1, 1):
                    leaf(d, nx, ny, ang + sd * 1.0, lw, lw * 0.28, c) if i % 2 == 0 else None
            x, y = nx, ny
    return im

def cell_broad(rnd, S):
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    for f in range(9):
        a = -math.pi / 2 + rnd.uniform(-1.1, 1.1)
        L = S * rnd.uniform(0.25, 0.5)
        sx, sy = S / 2 + rnd.uniform(-10, 10), S * 0.98
        ex, ey = sx + math.cos(a) * L * 0.6, sy + math.sin(a) * L * 0.6
        d.line([(sx, sy), (ex, ey)], fill=(50, 80, 30, 255), width=3)
        g = rnd.uniform(0.7, 1.1)
        leaf(d, ex, ey, a + rnd.uniform(-0.4, 0.4), L * 0.9, L * 0.3, (int(30 * g), int(120 * g), int(45 * g), 255))
    return im.filter(ImageFilter.SMOOTH)

def cell_reeds(rnd, S):
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    for f in range(26):
        x = S / 2 + rnd.uniform(-S * 0.3, S * 0.3); L = S * rnd.uniform(0.4, 0.95)
        a = -math.pi / 2 + rnd.uniform(-0.35, 0.35)
        g = rnd.uniform(0.7, 1.2)
        leaf(d, x, S * 0.99, a, L, S * 0.012, (int(60 * g), int(110 * g), int(35 * g), 255))
    return im

def cell_glow(rnd, S):
    # Leuchtpilze: kleine Gruppe, helle Hüte (leuchten im Spiel), dunklere Stiele
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    ms = []
    for f in range(7):
        ms.append((S / 2 + rnd.uniform(-S * 0.3, S * 0.3), rnd.uniform(0.35, 1.0)))
    ms.sort(key=lambda m: m[1])
    for x, sz in ms:
        h = S * 0.26 * sz; w = S * 0.15 * sz
        base = S * 0.99
        d.rounded_rectangle([x - w * 0.26, base - h, x + w * 0.26, base], radius=int(w * 0.15) + 1, fill=(70, 75, 70, 255))
        cap = [x - w, base - h - w * 0.9, x + w, base - h + w * 0.9]
        d.pieslice(cap, 180, 360, fill=(255, 255, 255, 255))
        d.ellipse([x - w * 0.95, base - h - w * 0.12, x + w * 0.95, base - h + w * 0.12], fill=(200, 200, 200, 255))
        for k in range(3):
            dx = rnd.uniform(-0.6, 0.6) * w; dy = rnd.uniform(-0.45, -0.15) * w
            r = w * 0.09
            d.ellipse([x + dx - r, base - h + dy - r, x + dx + r, base - h + dy + r], fill=(170, 170, 170, 255))
    return im

def under_atlas(dst):
    rnd = random.Random(7); S = 512
    o = Image.new('RGBA', (S * 4, S), (0, 0, 0, 0))
    for i, fn in enumerate([cell_fern, cell_broad, cell_reeds, cell_glow]):
        o.paste(fn(rnd, S), (i * S, 0))
    dilate(o).save(dst)

if __name__ == '__main__':
    tree_atlas(sys.argv[1], sys.argv[2])
    under_atlas(sys.argv[3])
