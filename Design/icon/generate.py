#!/usr/bin/env python3
"""Generates the Notchy icon SVGs from one set of measurements.

Geometry is in "body units": 0..1 across the squircle, measured from
Design/logo-candidates/notch-b3-smallerface.png. Change numbers here, rerun,
then run render.swift to rebuild the PNGs.
"""
import math, os

OUT = os.path.dirname(os.path.abspath(__file__))

# Notch: hangs from the top edge of the body.
NOTCH_L, NOTCH_R = 0.162, 0.838      # left/right edges
NOTCH_B = 0.684                      # bottom edge
NOTCH_RADIUS = 0.225                 # bottom corners
NOTCH_FILLET = 0.045                 # inverted fillets where it meets the top edge

# Face, centered in x at 0.5. FACE_DY moves the whole face vertically.
FACE_DY = -0.04
EYE_X, EYE_W, EYE_Y, EYE_H = 0.340, 0.0615, 0.250, 0.0877   # left eye; right is mirrored
NOSE_X, NOSE_TOP, NOSE_W = 0.500, 0.282, 0.0525             # stroke centerline + width
NOSE_HOOK_Y, NOSE_CORNER, NOSE_END_X = 0.420, 0.035, 0.460
SMILE_HALF, SMILE_Y, SMILE_SAG, SMILE_W = 0.114, 0.483, 0.051, 0.052

def f(v): return f"{v:.3f}".rstrip("0").rstrip(".")

def face_paths(tx, ty, s):
    """Face as filled outlines (no strokes), so it can be knocked out of the glyph."""
    X = lambda x: f(tx + x * s)
    Y = lambda y: f(ty + (y + FACE_DY) * s)
    L = lambda l: f(l * s)
    paths = []
    for ex in (EYE_X, 1 - EYE_X - EYE_W):
        r = EYE_W / 2
        x0, x1, y0, y1 = ex, ex + EYE_W, EYE_Y, EYE_Y + EYE_H
        paths.append(f"M{X(x0)} {Y(y0 + r)}A{L(r)} {L(r)} 0 0 1 {X(x1)} {Y(y0 + r)}"
                     f"V{Y(y1 - r)}A{L(r)} {L(r)} 0 0 1 {X(x0)} {Y(y1 - r)}Z")
    w = NOSE_W / 2
    cx, cy = NOSE_X - NOSE_CORNER, NOSE_HOOK_Y - NOSE_CORNER  # corner arc center
    ro, ri = NOSE_CORNER + w, NOSE_CORNER - w
    paths.append(
        f"M{X(NOSE_X - w)} {Y(NOSE_TOP)}A{L(w)} {L(w)} 0 0 1 {X(NOSE_X + w)} {Y(NOSE_TOP)}"
        f"V{Y(cy)}A{L(ro)} {L(ro)} 0 0 1 {X(cx)} {Y(cy + ro)}"
        f"H{X(NOSE_END_X)}A{L(w)} {L(w)} 0 0 1 {X(NOSE_END_X)} {Y(cy + ri)}"
        f"H{X(cx)}A{L(ri)} {L(ri)} 0 0 0 {X(NOSE_X - w)} {Y(cy)}Z")
    c, sag, h = SMILE_HALF, SMILE_SAG, SMILE_W / 2
    r = (c * c + sag * sag) / (2 * sag)
    ccx, ccy = 0.5, SMILE_Y + sag - r
    a1, a2 = math.atan2(SMILE_Y - ccy, -c), math.atan2(SMILE_Y - ccy, c)
    P = lambda rad, a: (X(ccx + rad * math.cos(a)), Y(ccy + rad * math.sin(a)))
    o1, o2, i1, i2 = P(r + h, a1), P(r + h, a2), P(r - h, a1), P(r - h, a2)
    paths.append(
        f"M{o1[0]} {o1[1]}A{L(r + h)} {L(r + h)} 0 0 0 {o2[0]} {o2[1]}"
        f"A{L(h)} {L(h)} 0 0 0 {i2[0]} {i2[1]}"
        f"A{L(r - h)} {L(r - h)} 0 0 1 {i1[0]} {i1[1]}"
        f"A{L(h)} {L(h)} 0 0 0 {o1[0]} {o1[1]}Z")
    return paths

def notch_path(tx, ty, s, top_overshoot=0.05):
    X = lambda x: f(tx + x * s)
    Y = lambda y: f(ty + y * s)
    R, F = NOTCH_RADIUS * s, NOTCH_FILLET * s
    return (f"M{X(NOTCH_L - NOTCH_FILLET)} {Y(-top_overshoot)}V{Y(0)}"
            f"Q{X(NOTCH_L)} {Y(0)} {X(NOTCH_L)} {Y(NOTCH_FILLET)}"
            f"V{Y(NOTCH_B - NOTCH_RADIUS)}A{f(R)} {f(R)} 0 0 0 {X(NOTCH_L + NOTCH_RADIUS)} {Y(NOTCH_B)}"
            f"H{X(NOTCH_R - NOTCH_RADIUS)}A{f(R)} {f(R)} 0 0 0 {X(NOTCH_R)} {Y(NOTCH_B - NOTCH_RADIUS)}"
            f"V{Y(NOTCH_FILLET)}Q{X(NOTCH_R)} {Y(0)} {X(NOTCH_R + NOTCH_FILLET)} {Y(0)}"
            f"V{Y(-top_overshoot)}Z")

INDIGO_TOP, INDIGO_MID, INDIGO_BOTTOM = "#141c72", "#080c4c", "#03032a"
VIOLET, NOTCH_BLACK, FACE_WHITE = "#7a4dff", "#050509", "#f6f6fa"

def app_icon():
    # macOS icon grid: 824pt body centered on a 1024 canvas.
    o, s, rad = 100, 824, 184
    face = "".join(f'<path d="{p}"/>' for p in face_paths(o, o, s))
    notch = notch_path(o, o, s)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
  <linearGradient id="body" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="{INDIGO_TOP}"/><stop offset=".45" stop-color="{INDIGO_MID}"/><stop offset="1" stop-color="{INDIGO_BOTTOM}"/>
  </linearGradient>
  <linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity=".22"/><stop offset=".22" stop-color="#fff" stop-opacity="0"/>
  </linearGradient>
  <clipPath id="clip"><rect x="{o}" y="{o}" width="{s}" height="{s}" rx="{rad}"/></clipPath>
  <filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="9"/></filter>
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="150%"><feGaussianBlur stdDeviation="10"/></filter>
</defs>
<rect x="{o}" y="{o + 10}" width="{s}" height="{s}" rx="{rad}" fill="#000" opacity=".35" filter="url(#shadow)"/>
<g clip-path="url(#clip)">
  <rect x="{o}" y="{o}" width="{s}" height="{s}" fill="url(#body)"/>
  <rect x="{o}" y="{o}" width="{s}" height="{s}" fill="url(#gloss)"/>
  <rect x="{o}" y="{o}" width="{s}" height="{s}" rx="{rad}" fill="none" stroke="{VIOLET}" stroke-width="22" opacity=".55" filter="url(#soft)"/>
  <path d="{notch}" fill="none" stroke="{VIOLET}" stroke-width="16" opacity=".8" filter="url(#soft)"/>
  <path d="{notch}" fill="{NOTCH_BLACK}" stroke="{VIOLET}" stroke-width="2.5" stroke-opacity=".7"/>
  <g fill="{FACE_WHITE}">{face}</g>
</g>
<rect x="{o + 1.5}" y="{o + 1.5}" width="{s - 3}" height="{s - 3}" rx="{rad - 1.5}" fill="none" stroke="{VIOLET}" stroke-width="3"/>
</svg>
'''

def menubar_glyph():
    # 18x18pt template image: the notch silhouette with the face knocked out.
    s = 22.0                  # body units -> points
    tx = 9 - 0.5 * s          # center horizontally
    ty = 1.0
    notch = notch_path(tx, ty, s, top_overshoot=0)
    face = "".join(face_paths(tx, ty, s))
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
<path fill-rule="evenodd" fill="#000" d="{notch}{face}"/>
</svg>
'''

for name, svg in [("notchy-icon.svg", app_icon()), ("menubar-glyph.svg", menubar_glyph())]:
    with open(os.path.join(OUT, name), "w") as fh:
        fh.write(svg)
    print("wrote", name)
