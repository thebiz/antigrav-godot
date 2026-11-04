# R-37: Lackierung aus der Tripo-Textur säubern und scharfe Decals in UV-Raum backen
import numpy as np, math, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from scipy import ndimage as nd

N = 2048
d = np.load('maps.npz'); P, NM, M = d['P'], d['N'], d['M']
def load(f):
    return np.asarray(Image.open(f).convert('RGB').resize((N, N), Image.LANCZOS)).astype(np.float32) / 255.0
C = load('../glb/img0.jpg'); MR = load('../glb/img1.jpg'); NRM = load('../glb/img2.png')

r, g, b = C[..., 0], C[..., 1], C[..., 2]
L = 0.3 * r + 0.59 * g + 0.11 * b
mx, mn = C.max(-1), C.min(-1)
red = r - np.maximum(g, b)
cls = np.zeros((N, N), int)                       # 0 dunkel
cls[(L > 0.4) & (mx - mn < 0.2)] = 1              # weiß
cls[(red > 0.18) & (r > 0.28)] = 2                # rot
cls[(b - r > 0.12) & (b > 0.42)] = 3              # blau leuchtend
# KI-Gekritzel weg: dünne dunkle Striche in weißen Flächen schließen, rote Sprenkel öffnen
def disk(r):
    y, x = np.mgrid[-r:r + 1, -r:r + 1]; return x * x + y * y <= r * r
wh = cls == 1
wc = nd.binary_closing(wh, disk(5)) & M
loc = nd.uniform_filter(wh.astype(np.float32), 25)
cls[wc & (cls == 0) & (loc > 0.35)] = 1
rd = cls == 2
ro = nd.binary_opening(rd, disk(4))
cls[rd & ~ro & (loc > 0.3)] = 1
rd = cls == 2
ro = nd.binary_opening(rd, disk(9))
cls[rd & ~ro & (loc > 0.45)] = 1
wh = cls == 1
wc = nd.binary_closing(wh, disk(7)) & M
cls[wc & (cls == 0) & (loc > 0.5)] = 1
# kleine dunkle/rote Inseln mitten im Weiß -> Weiß
def _clean(k, amax, frac):
    m = (cls == k) & M
    lab, n = nd.label(m)
    if n == 0: return
    area = np.bincount(lab.ravel(), minlength=n + 1)
    grown = nd.grey_dilation(lab, footprint=disk(2))
    ring = (grown > 0) & ~m & M
    tot = np.bincount(grown[ring], minlength=n + 1)
    wt = np.bincount(grown[ring & (cls == 1)], minlength=n + 1)
    ok = (area < amax) & (wt > frac * np.maximum(tot, 1))
    ok[0] = False
    cls[ok[lab] & m] = 1
for _ in range(2):
    _clean(0, 2500, 0.6)
    _clean(2, 1200, 0.6)
# Flächen, auf die neue Decals kommen, vorher glatt machen
def box(lo, hi, nrm_ax=None, sgn=0):
    sel = M & np.all((P >= lo) & (P <= hi), -1)
    if nrm_ax is not None:
        sel &= NM[..., nrm_ax] * sgn > 0.4
    return sel
for sd in (1, -1):
    xs_ = sorted([sd * 0.12, sd * 0.3])
    sb = box((xs_[0], 0.06, -0.035), (xs_[1], 0.115, 0.045), 0, sd); cls[sb & (cls != 2)] = 0
    sb = box((xs_[0], 0.085, -0.15), (xs_[1], 0.14, -0.085), 0, sd); cls[sb & (cls == 0)] = 1
# Rot nicht von der KI übernehmen (Kleckse), sondern gezielt als Rennlackierung setzen
cls[cls == 2] = 1
px, py, pz = P[..., 0], P[..., 1], P[..., 2]
ax_ = np.abs(px); light = M & (cls == 1)
side = np.abs(NM[..., 0]) > 0.35
top = NM[..., 1] > 0.45
q = pz + 0.9 * (py - 0.08)
redm = np.zeros_like(M)
redm |= side & (ax_ > 0.1) & (py > 0.035) & (py < 0.15) & (((q > -0.082) & (q < -0.05)) | ((q > -0.104) & (q < -0.092)))
redm |= (ax_ > 0.045) & (pz > 0.335)
redm |= (ax_ > 0.165) & (pz < -0.24)
redm |= top & (ax_ < 0.013) & (pz < -0.17)
q2 = pz - 1.3 * (ax_ - 0.07)
redm |= top & (ax_ > 0.07) & (q2 > 0.255) & (q2 < 0.28)
cls[light & redm] = 2
Mf = M.astype(np.float32)
def mblur(a, s):
    return nd.gaussian_filter(a * Mf, s) / np.maximum(nd.gaussian_filter(Mf, s), 1e-4)
W = np.stack([mblur((cls == k).astype(np.float32), 2.6) for k in range(4)], -1)
W = W ** 5; W /= W.sum(-1, keepdims=True) + 1e-6
# Lackfarben mit sanfter Schattierung aus dem Original (nur grobe Helligkeit)
Lb = mblur(L, 10.0)
def shade(k, ref):
    return np.clip(Lb / ref, 0.94, 1.03)[..., None]
WHITE = np.array([0.84, 0.83, 0.80]); REDC = np.array([0.66, 0.025, 0.045])
gray = C.mean(-1, keepdims=True)
dark = (C * 0.45 + gray * 0.55) * 0.85
col = (W[..., 1:2] * WHITE * shade(1, 0.72) + W[..., 2:3] * REDC * shade(2, 0.3)
       + W[..., 0:1] * dark + W[..., 3:4] * np.clip(C * 1.15, 0, 1))
rough = W[..., 1] * 0.42 + W[..., 2] * 0.4 + W[..., 0] * MR[..., 1] + W[..., 3] * 0.2
metal = W[..., 1] * 0.0 + W[..., 2] * 0.05 + W[..., 0] * np.maximum(MR[..., 2], 0.45) + W[..., 3] * 0.1
emis = W[..., 3:4] * np.clip(C * 1.3, 0, 1)
white_w = W[..., 1]

# --------------------------------------------------------------- Decals
def font(path, size):
    return ImageFont.truetype(path, size)
def text_img(txt, fpath, size, fill, stroke=0, sfill=None, skew=0.0, idx=0):
    f = ImageFont.truetype(fpath, size, index=idx)
    bb = f.getbbox(txt, stroke_width=stroke)
    w, h = bb[2] - bb[0] + 40, bb[3] - bb[1] + 40
    im = Image.new('RGBA', (w + int(abs(skew) * h), h), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((20 - bb[0], 20 - bb[1]), txt, font=f, fill=fill, stroke_width=stroke, stroke_fill=sfill)
    if skew:
        im = im.transform(im.size, Image.AFFINE, (1, skew, -skew * h * 0.0, 0, 1, 0), Image.BICUBIC)
    return im

def decal(img, c, u, v, w, h, n, thr=0.45, depth=0.06, only_white=False, opacity=1.0, rough_v=None):
    global col, rough, metal
    c, u, v, n = map(np.asarray, (c, u, v, n))
    A = np.asarray(img).astype(np.float32) / 255.0
    H_, W_ = A.shape[:2]
    rel = P - c
    s = (rel @ u) / w + 0.5
    t = 0.5 - (rel @ v) / h
    dd = np.abs(rel @ n)
    sel = M & (NM @ n > thr) & (s >= 0) & (s < 1) & (t >= 0) & (t < 1) & (dd < depth)
    ys, xs = np.nonzero(sel)
    sx = s[ys, xs] * (W_ - 1); ty = t[ys, xs] * (H_ - 1)
    # bilinear
    x0 = np.floor(sx).astype(int); y0 = np.floor(ty).astype(int)
    x1 = np.minimum(x0 + 1, W_ - 1); y1 = np.minimum(y0 + 1, H_ - 1)
    fx = (sx - x0)[:, None]; fy = (ty - y0)[:, None]
    smp = (A[y0, x0] * (1 - fx) * (1 - fy) + A[y0, x1] * fx * (1 - fy) + A[y1, x0] * (1 - fx) * fy + A[y1, x1] * fx * fy)
    a = smp[:, 3:4] * opacity
    if only_white:
        a = a * np.clip(white_w[ys, xs] * 1.4 - 0.2, 0, 1)[:, None]
    col[ys, xs] = col[ys, xs] * (1 - a) + smp[:, :3] * a
    if rough_v is not None:
        rough[ys, xs] = rough[ys, xs] * (1 - a[:, 0]) + rough_v * a[:, 0]
        metal[ys, xs] = metal[ys, xs] * (1 - a[:, 0])

FNUM = '/usr/share/fonts/opentype/inter/InterDisplay-BlackItalic.otf'
FCJK = '/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc'
n37 = text_img('37', FNUM, 300, (240, 236, 228, 255), stroke=10, sfill=(150, 8, 14, 255))
dragon = text_img('龍', FCJK, 300, (14, 12, 12, 255), idx=0)
dragon_w = text_img('龍', FCJK, 300, (236, 232, 224, 255), idx=0)

# Kirschblütenzweig (prozedural): schwarze Äste mit roten Blüten
def blossom(w=1400, h=500, seed=3):
    rnd = random.Random(seed)
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0)); dr = ImageDraw.Draw(im)
    flowers = []
    def branch(x, y, ang, ln, th, dep):
        for i in range(int(ln / 14)):
            ang += rnd.uniform(-0.18, 0.18)
            nx, ny = x + math.cos(ang) * 14, y + math.sin(ang) * 14
            dr.line((x, y, nx, ny), fill=(18, 14, 14, 255), width=max(2, int(th)))
            x, y = nx, ny; th *= 0.985
            if dep < 3 and rnd.random() < 0.09:
                branch(x, y, ang + rnd.choice([-1, 1]) * rnd.uniform(0.5, 1.0), ln * 0.45, th * 0.6, dep + 1)
            if th < 9 and rnd.random() < 0.22:
                flowers.append((x + rnd.uniform(-10, 10), y + rnd.uniform(-10, 10), rnd.uniform(9, 17)))
        flowers.append((x, y, 14))
    branch(10, h * 0.7, -0.12, w * 0.95, 20, 0)
    for (x, y, r_) in flowers:
        rot = rnd.uniform(0, 6.28)
        for k in range(5):
            a = rot + k * 1.2566
            px, py = x + math.cos(a) * r_ * 0.6, y + math.sin(a) * r_ * 0.6
            dr.ellipse((px - r_ * 0.55, py - r_ * 0.55, px + r_ * 0.55, py + r_ * 0.55), fill=(196, 22, 40, 255))
        dr.ellipse((x - r_ * 0.25, y - r_ * 0.25, x + r_ * 0.25, y + r_ * 0.25), fill=(255, 214, 120, 255))
    return im

X, Y, Z = np.eye(3)
for sd in (1, -1):
    u = -Z if sd > 0 else Z
    decal(n37, (sd * 0.2, 0.086, 0.004), u, Y, 0.085, 0.05, sd * X, thr=0.45, depth=0.05, rough_v=0.25)
    bl = blossom(seed=5 if sd > 0 else 9)
    decal(bl, (sd * 0.15, 0.12, -0.13), Z, -X, 0.28, 0.1, Y, thr=0.65, depth=0.2, only_white=True, opacity=0.95, rough_v=0.3)
    decal(dragon, (sd * 0.2, 0.1, -0.122), u, Y, 0.036, 0.036, sd * X, thr=0.45, depth=0.05, rough_v=0.3)
# oben vorn auf den Außenrümpfen: Nummer links im Bild, Drache rechts (Nase nach oben lesbar)
decal(n37, (0.135, 0.13, 0.185), -X, Z, 0.075, 0.044, Y, thr=0.5, depth=0.2, rough_v=0.25)
decal(dragon, (-0.135, 0.13, 0.19), -X, Z, 0.045, 0.045, Y, thr=0.5, depth=0.2, rough_v=0.3)
# Ränder der UV-Inseln auffüllen (gegen Nähte bei Mipmaps)
def dilate(a, it=6):
    a = a.copy(); m = M.copy()
    for _ in range(it):
        acc = np.zeros_like(a); cnt = np.zeros(m.shape, np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            acc += np.roll(np.roll(a * m[..., None] if a.ndim == 3 else a * m, dy, 0), dx, 1)
            cnt += np.roll(np.roll(m, dy, 0), dx, 1)
        nm = (~m) & (cnt > 0)
        if a.ndim == 3:
            a[nm] = acc[nm] / cnt[nm][:, None]
        else:
            a[nm] = acc[nm] / cnt[nm]
        m = m | nm
    return a
col = dilate(np.clip(col, 0, 1)); rough = dilate(np.clip(rough, 0.05, 1)); metal = dilate(np.clip(metal, 0, 1)); emis = dilate(emis)
Image.fromarray((col * 255).astype(np.uint8)).save('r37_col.png')
mr = np.stack([np.ones_like(rough), rough, metal], -1)
Image.fromarray((mr * 255).astype(np.uint8)).save('r37_mr.png')
Image.fromarray((np.clip(emis, 0, 1) * 255).astype(np.uint8)).save('r37_emis.png')
# Normalmap: KI-Prägung der Schriftzeichen weich machen, Paneele bleiben
nn = NRM * 2 - 1
nn = np.stack([nd.gaussian_filter(nn[..., k], 4.0) for k in range(3)], -1)
nn[..., :2] *= 0.35
nn /= np.linalg.norm(nn, axis=-1, keepdims=True) + 1e-6
Image.fromarray(((nn * 0.5 + 0.5) * 255).astype(np.uint8)).save('r37_nrm.png')
print('done')
