"""Geometric invariant checks for generated ERD documents (plan g1_erd_plan.md section 6)."""

from diagram_tool.core import geometry
from diagram_tool.kinds.raw import validate_raw


def polylines(doc):
    """{edge id: [(x, y)...]} absolute (all edges are page-level) and {table id: (x, y, w, h)}."""
    page = validate_raw(doc).doc["pages"][0]
    by_id = {c["id"]: c for c in page["cells"]}
    tables = {c["id"]: (c["x"], c["y"], c["w"], c["h"]) for c in page["cells"] if c["type"] == "table"}
    lines = {}
    for c in page["cells"]:
        if c["type"] != "edge":
            continue
        if c["exit"] is None:
            raise AssertionError("edge %s has no exit port" % c["id"])
        p0, pn = geometry.edge_endpoints(by_id, c)
        lines[c["id"]] = [p0] + [(p["x"], p["y"]) for p in c["points"]] + [pn]
    return lines, tables


def segments(lines):
    out = []
    for eid, pts in lines.items():
        for a, b in zip(pts, pts[1:]):
            out.append((eid, a, b))
    return out


def _span(a, b, axis):
    lo, hi = sorted((a[axis], b[axis]))
    return lo, hi


def overlapping_segments(lines):
    """Pairs of segments of DIFFERENT edges that lie on the same line and share a stretch (> 0.5 px)."""
    segs = segments(lines)
    bad = []
    for i, (e1, a1, b1) in enumerate(segs):
        v1 = abs(a1[0] - b1[0]) < 1e-9
        for e2, a2, b2 in segs[i + 1:]:
            if e1 == e2:
                continue
            v2 = abs(a2[0] - b2[0]) < 1e-9
            if v1 != v2:
                continue
            if v1:
                if abs(a1[0] - a2[0]) > 1e-9:
                    continue
                lo = max(_span(a1, b1, 1)[0], _span(a2, b2, 1)[0])
                hi = min(_span(a1, b1, 1)[1], _span(a2, b2, 1)[1])
            else:
                if abs(a1[1] - a2[1]) > 1e-9:
                    continue
                lo = max(_span(a1, b1, 0)[0], _span(a2, b2, 0)[0])
                hi = min(_span(a1, b1, 0)[1], _span(a2, b2, 0)[1])
            if hi - lo > 0.5:
                bad.append((e1, e2, (a1, b1), (a2, b2)))
    return bad


def crossings(lines):
    """Number of proper crossings between a horizontal and a vertical segment of different edges."""
    segs = segments(lines)
    horizontals = [(e, a, b) for e, a, b in segs if abs(a[1] - b[1]) < 1e-9 and abs(a[0] - b[0]) > 1e-9]
    verticals = [(e, a, b) for e, a, b in segs if abs(a[0] - b[0]) < 1e-9 and abs(a[1] - b[1]) > 1e-9]
    total = 0
    for eh, a, b in horizontals:
        x_lo, x_hi = sorted((a[0], b[0]))
        for ev, c, d in verticals:
            if eh == ev:
                continue
            y_lo, y_hi = sorted((c[1], d[1]))
            if x_lo < c[0] < x_hi and y_lo < a[1] < y_hi:
                total += 1
    return total


def segments_through_tables(lines, tables, margin=1):
    """Segments that enter the interior of a table (shrunk by `margin`)."""
    bad = []
    for eid, a, b in segments(lines):
        lo_x, hi_x = sorted((a[0], b[0]))
        lo_y, hi_y = sorted((a[1], b[1]))
        for name, (x, y, w, h) in tables.items():
            if lo_x < x + w - margin and hi_x > x + margin and lo_y < y + h - margin and hi_y > y + margin:
                bad.append((eid, name))
    return bad


def min_clearance(lines, tables):
    """Smallest distance between a segment and a table it does NOT start/end on (None if no pair)."""
    best = None
    for eid, a, b in segments(lines):
        lo_x, hi_x = sorted((a[0], b[0]))
        lo_y, hi_y = sorted((a[1], b[1]))
        for name, (x, y, w, h) in tables.items():
            touches = any(x - 1e-9 <= p[0] <= x + w + 1e-9 and y - 1e-9 <= p[1] <= y + h + 1e-9 for p in (a, b))
            if touches:
                continue
            dx = max(x - hi_x, lo_x - (x + w), 0)
            dy = max(y - hi_y, lo_y - (y + h), 0)
            d = (dx * dx + dy * dy) ** 0.5
            if best is None or d < best:
                best = d
    return best


def stub_lengths(lines):
    """Length of the first and last segment of each edge."""
    out = {}
    for eid, pts in lines.items():
        first = abs(pts[1][0] - pts[0][0]) + abs(pts[1][1] - pts[0][1])
        last = abs(pts[-1][0] - pts[-2][0]) + abs(pts[-1][1] - pts[-2][1])
        out[eid] = (first, last)
    return out
