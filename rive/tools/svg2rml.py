#!/usr/bin/env python3
"""svg2rml — turn an SVG path `d` into RML <PointsPath> elements.

Why this exists: the fuime arch is a real glyph with counters (holes), and a
hand-placed approximation of it is a different logo. Rive's PointsPath carries
the same cubic information an SVG path does, just expressed as polar handles
(rotation + distance from the vertex) instead of absolute control points, so the
conversion is exact rather than a trace.

  in-handle  = the control point that ends the segment ARRIVING at this vertex
  out-handle = the control point that starts the segment LEAVING it

Both are written as an angle in radians and a distance, which is what
CubicDetachedVertex takes. A vertex with neither handle is a StraightVertex.

Usage: svg2rml.py <file.svg> [--scale S] [--translate X Y] [--fit W H]
"""
import math, re, sys, xml.etree.ElementTree as ET

NUM = re.compile(r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?')
CMD = re.compile(r'([MmLlHhVvCcSsZz])')


def parse_path(d):
    """SVG path -> list of subpaths; each a list of (pt, in_cp|None, out_cp|None)."""
    toks, i = CMD.split(d), 0
    subpaths, cur = [], None
    pos = (0.0, 0.0)
    start = (0.0, 0.0)
    prev_c2 = None          # for S/s smooth continuation
    cmd = None
    parts = [t for t in toks if t.strip()]
    k = 0
    while k < len(parts):
        tok = parts[k]
        if CMD.fullmatch(tok):
            cmd = tok
            k += 1
            args = [float(n) for n in NUM.findall(parts[k])] if k < len(parts) and not CMD.fullmatch(parts[k]) else []
            if args:
                k += 1
        else:
            args = [float(n) for n in NUM.findall(tok)]
            k += 1
        rel = cmd.islower()
        c = cmd.upper()

        def A(x, y):
            return (pos[0] + x, pos[1] + y) if rel else (x, y)

        if c == 'M':
            j = 0
            while j < len(args):
                p = A(args[j], args[j + 1])
                if j == 0:
                    if cur:
                        subpaths.append(cur)
                    cur = [[p, None, None]]
                    start = p
                else:
                    cur.append([p, None, None])
                pos = p
                j += 2
            prev_c2 = None
        elif c in 'LHV':
            j = 0
            step = {'L': 2, 'H': 1, 'V': 1}[c]
            while j < len(args):
                if c == 'L':
                    p = A(args[j], args[j + 1])
                elif c == 'H':
                    p = (pos[0] + args[j], pos[1]) if rel else (args[j], pos[1])
                else:
                    p = (pos[0], pos[1] + args[j]) if rel else (pos[0], args[j])
                cur.append([p, None, None])
                pos = p
                j += step
            prev_c2 = None
        elif c in 'CS':
            j = 0
            step = 6 if c == 'C' else 4
            while j < len(args):
                if c == 'C':
                    c1 = A(args[j], args[j + 1])
                    c2 = A(args[j + 2], args[j + 3])
                    p = A(args[j + 4], args[j + 5])
                else:
                    c1 = (2 * pos[0] - prev_c2[0], 2 * pos[1] - prev_c2[1]) if prev_c2 else pos
                    c2 = A(args[j], args[j + 1])
                    p = A(args[j + 2], args[j + 3])
                cur[-1][2] = c1          # out-handle of the vertex we are leaving
                cur.append([p, c2, None])  # in-handle of the vertex we arrive at
                pos = p
                prev_c2 = c2
                j += step
        elif c == 'Z':
            if cur:
                # A closing segment back to the start; if the last point equals
                # the start, fold it away so the path closes on one vertex.
                if len(cur) > 1 and math.dist(cur[-1][0], start) < 1e-6:
                    tail = cur.pop()
                    if tail[1] is not None:
                        cur[0][1] = tail[1]
                subpaths.append(cur)
                cur = None
            pos = start
            prev_c2 = None
    if cur:
        subpaths.append(cur)
    return subpaths


def polar(vertex, cp):
    """Handle as (rotation radians, distance) measured from the vertex."""
    if cp is None:
        return (0.0, 0.0)
    dx, dy = cp[0] - vertex[0], cp[1] - vertex[1]
    return (math.atan2(dy, dx), math.hypot(dx, dy))


def to_rml(subpaths, xf, indent='    '):
    out = []
    for si, sp in enumerate(subpaths):
        out.append(f'{indent}<PointsPath isClosed="true" name="c{si}">')
        for (p, ic, oc) in sp:
            P, IC, OC = xf(p), xf(ic), xf(oc)
            ir, idist = polar(P, IC)
            orr, odist = polar(P, OC)
            if idist < 1e-6 and odist < 1e-6:
                out.append(f'{indent}    <StraightVertex x="{P[0]:.3f}" y="{P[1]:.3f}"/>')
            else:
                out.append(
                    f'{indent}    <CubicDetachedVertex x="{P[0]:.3f}" y="{P[1]:.3f}"'
                    f' inRotation="{ir:.5f}" inDistance="{idist:.3f}"'
                    f' outRotation="{orr:.5f}" outDistance="{odist:.3f}"/>')
        out.append(f'{indent}</PointsPath>')
    return '\n'.join(out)


def main():
    src = sys.argv[1]
    args = sys.argv[2:]

    def flag(name, n=1, default=None):
        if name in args:
            i = args.index(name)
            vals = [float(v) for v in args[i + 1:i + 1 + n]]
            return vals if n > 1 else vals[0]
        return default

    tree = ET.parse(src)
    root = tree.getroot()
    ns = {'s': 'http://www.w3.org/2000/svg'}
    path_el = root.find('.//s:path', ns)
    g = root.find('.//s:g', ns)
    d = path_el.get('d')

    # The glyph carries its own transform on the <g>; apply it before anything.
    gt = (g.get('transform') or '') if g is not None else ''
    tx = ty = 0.0
    sx = sy = 1.0
    m = re.search(r'translate\(([-\d.]+)[,\s]+([-\d.]+)\)', gt)
    if m:
        tx, ty = float(m.group(1)), float(m.group(2))
    m = re.search(r'scale\(([-\d.]+)[,\s]+([-\d.]+)\)', gt)
    if m:
        sx, sy = float(m.group(1)), float(m.group(2))

    subpaths = parse_path(d)

    def base(p):
        return (p[0] * sx + tx, p[1] * sy + ty)

    pts = [base(v[0]) for sp in subpaths for v in sp]
    minx, maxx = min(p[0] for p in pts), max(p[0] for p in pts)
    miny, maxy = min(p[1] for p in pts), max(p[1] for p in pts)

    fit = flag('--fit', 2)
    scale = flag('--scale', 1, 1.0)
    trans = flag('--translate', 2, [0.0, 0.0])
    if fit:
        scale = min(fit[0] / (maxx - minx), fit[1] / (maxy - miny))

    cx, cy = (minx + maxx) / 2, (miny + maxy) / 2

    def xf(p):
        if p is None:
            return None
        q = base(p)
        return ((q[0] - cx) * scale + trans[0], (q[1] - cy) * scale + trans[1])

    sys.stderr.write(
        f'{len(subpaths)} subpaths, {len(pts)} vertices; '
        f'source bbox {maxx-minx:.1f}x{maxy-miny:.1f} -> scale {scale:.4f}\n')
    print(to_rml(subpaths, xf))


if __name__ == '__main__':
    main()
