#!/usr/bin/env python3
"""Verifica que un diagrama de clases PlantUML (SVG) no tenga relaciones cruzadas.

Uso:  python check_crossings.py diagrama.svg

Comprueba, a partir del SVG generado por PlantUML:
  1. Que ningún par de relaciones (<g class="link">) se intersecte entre sí.
  2. Que ninguna relación atraviese una clase que no sea uno de sus extremos.
Código de salida: 0 = sin cruces, 1 = hay cruces o atravesamientos.
"""
import re
import sys
import xml.etree.ElementTree as ET

NS = {"s": "http://www.w3.org/2000/svg"}
EPS = 3.0  # tolerancia en px alrededor de los extremos de cada relación


def local(tag):
    return tag.split("}")[-1]


def points_of(d):
    nums = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", d)]
    return list(zip(nums[0::2], nums[1::2]))


def segments(pts):
    return list(zip(pts[:-1], pts[1:]))


def ccw(a, b, c):
    return (c[1] - a[1]) * (b[0] - a[0]) - (b[1] - a[1]) * (c[0] - a[0])


def intersect(s1, s2):
    a, b = s1
    c, d = s2
    d1, d2 = ccw(a, b, c), ccw(a, b, d)
    d3, d4 = ccw(c, d, a), ccw(c, d, b)
    return d1 * d2 < 0 and d3 * d4 < 0


def near_end(p, ends):
    return any(abs(p[0] - e[0]) <= EPS and abs(p[1] - e[1]) <= EPS for e in ends)


def seg_hits_rect(seg, rect):
    x, y, w, h = rect
    x0, y0, x1, y1 = x + 2, y + 2, x + w - 2, y + h - 2  # interior
    (ax, ay), (bx, by) = seg
    for t in [i / 40 for i in range(41)]:
        px, py = ax + (bx - ax) * t, ay + (by - ay) * t
        if x0 < px < x1 and y0 < py < y1:
            return True
    return False


def attr(tag, name):
    m = re.search(r'\b' + name + r'="([^"]*)"', tag)
    return m.group(1) if m else None


def main(path):
    svg = open(path, encoding="utf-8").read()
    classes, links = {}, {}
    for tag in re.findall(r"<rect [^>]*>", svg):
        cid, w = attr(tag, "id"), attr(tag, "width")
        if cid and w and attr(tag, "height") and attr(tag, "x"):
            classes[cid] = (float(attr(tag, "x")), float(attr(tag, "y")), float(w), float(attr(tag, "height")))
    for tag in re.findall(r"<path [^>]*>", svg):
        lid, d = attr(tag, "id"), attr(tag, "d")
        if lid and d and attr(tag, "fill") == "none":
            links[lid] = points_of(d)

    def ends_of(lid):
        return {t for t in re.split(r"-(?:backto-|to-)?", lid) if t in classes}

    problems = []
    ids = list(links)
    for i, a in enumerate(ids):
        for b in ids[i + 1:]:
            for s1 in segments(links[a]):
                for s2 in segments(links[b]):
                    if intersect(s1, s2):
                        problems.append(f"CRUCE: {a}  x  {b}")
    for lid, pts in links.items():
        for cname, rect in classes.items():
            if cname in ends_of(lid):
                continue
            if any(seg_hits_rect(seg, rect) for seg in segments(pts)):
                problems.append(f"ATRAVIESA: {lid} pasa sobre la clase {cname}")

    print(f"relaciones: {len(links)}  clases: {len(classes)}")
    for p in sorted(set(problems)):
        print(p)
    print("OK: sin cruces" if not problems else f"FALLO: {len(set(problems))} problema(s)")
    return 1 if problems else 0

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))

