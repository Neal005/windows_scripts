"""Port of draw.io's mxEdgeStyle.SegmentConnector (mxgraph 32.6.9, mxEdgeStyle.js:600-912).

Used ONLY in tests, as the evidence that the corner list we write is the polyline draw.io
draws. `edgeStyle=orthogonalEdgeStyle` is OrthConnector, which delegates to SegmentConnector
whenever control points exist (`orthPointsFallback`, mxEdgeStyle.js:916 and 1187-1193).

Scope of the port: both end points are FIXED (exit/entry given), scale 1, translate 0.
In that case the source/target terminal "channels" are never consulted (they are guarded
by `currentTerm != null` / `pts[i] == null`), so they are not modelled. Rounding to 0.1
(`scalePointArray`, `pushPoint`) and the 1 px tolerance are reproduced. Not modelled:
perimeter projection of the end points (rounded shapes), floating ends, `innerLoopWaypoints`.

Frame: all coordinates are in one common frame (the coordinate frame of the edge parent;
draw.io adds the parent origin to the hints and works in absolute units, a pure translation).
"""

import math

TOL = 1


def _js_round(value):
    """JavaScript Math.round (half rounds toward +infinity)."""
    return math.floor(value + 0.5)


def _r1(value):
    return _js_round(value * 10) / 10


class _Pt:
    __slots__ = ("x", "y")

    def __init__(self, x, y):
        self.x = x
        self.y = y

    def clone(self):
        return _Pt(self.x, self.y)

    def as_tuple(self):
        return (self.x, self.y)


def segment_connector(start, end, hints):
    """Route between fixed end points `start` and `end` through control `hints`.

    start, end: (x, y). hints: list of (x, y) corner points (the `points` of the edge).
    Returns the full polyline [start, bend..., end] as a list of (x, y) tuples
    (draw.io's `result` holds start + bends; the end terminal is appended by the caller).
    """
    pts = [_Pt(_r1(start[0]), _r1(start[1])), _Pt(_r1(end[0]), _r1(end[1]))]
    last_inx = len(pts) - 1
    result = [pts[0].clone()]            # mxGraphView.updatePoints seeds result with the first terminal
    temp = []
    last_pushed = [result[0].clone()]    # boxed so the closure can rebind it

    def add_point(p):
        temp.append(p)

    def push_point(p):
        p.x = _r1(p.x)
        p.y = _r1(p.y)
        lp = last_pushed[0]
        if lp is None or abs(lp.x - p.x) >= TOL or abs(lp.y - p.y) >= TOL:
            result.append(p.clone())
            last_pushed[0] = p

    horizontal = True
    hint = None
    pt = pts[0].clone()
    # In the JS, `pe` is declared inside the `controlHints` block (mxEdgeStyle.js:693), so it is
    # undefined without hints and the final "remove last point inside tolerance" step is skipped.
    pe = None

    if hints:
        pe = pts[last_inx]
        hs = [_Pt(float(h[0]), float(h[1])) for h in hints]

        # Aligns first and last hint to the fixed end points
        if abs(hs[0].x - pt.x) < TOL:
            hs[0].x = pt.x
        if abs(hs[0].y - pt.y) < TOL:
            hs[0].y = pt.y
        if abs(hs[-1].x - pe.x) < TOL:
            hs[-1].x = pe.x
        if abs(hs[-1].y - pe.y) < TOL:
            hs[-1].y = pe.y

        hint = hs[0]
        current_pt = pts[0]
        current_hint = hint

        # Orientation of the first segment (fixed end points only: channels are not involved)
        for i in range(2):
            fixed_vert = current_pt is not None and current_pt.x == current_hint.x
            fixed_hoz = current_pt is not None and current_pt.y == current_hint.y
            hoz_chan = fixed_hoz
            vert_chan = fixed_vert

            if i == 0 and ((hoz_chan and vert_chan) or (fixed_vert and fixed_hoz)):
                pass
            elif vert_chan or hoz_chan:
                horizontal = hoz_chan
                if i == 1:
                    # Work back from the target end
                    horizontal = hoz_chan if len(hs) % 2 == 0 else vert_chan
                break

            current_pt = pts[last_inx]
            current_hint = hs[-1]
            if fixed_vert and fixed_hoz:
                hs = hs[1:]

        if horizontal and pts[0] is not None and pts[0].y != hint.y:
            add_point(_Pt(pt.x, hint.y))
        elif (not horizontal) and pts[0] is not None and pts[0].x != hint.x:
            add_point(_Pt(hint.x, pt.y))

        if horizontal:
            pt.y = hint.y
        else:
            pt.x = hint.x

        for h in hs:
            horizontal = not horizontal
            hint = h
            if horizontal:
                pt.y = hint.y
            else:
                pt.x = hint.x
            add_point(pt.clone())
    else:
        hint = pt
        horizontal = True

    # Adds the last point
    pt = pts[last_inx]
    if hint is not None:
        if horizontal and pts[last_inx].y != hint.y:
            add_point(_Pt(pt.x, hint.y))
        elif (not horizontal) and pts[last_inx].x != hint.x:
            add_point(_Pt(hint.x, pt.y))

    for p in temp:
        push_point(p)

    # Removes the last point if it is inside the tolerance of the end point
    if pe is not None and result and abs(pe.x - result[-1].x) <= TOL and abs(pe.y - result[-1].y) <= TOL:
        result.pop()
        if result:
            if abs(result[-1].x - pe.x) < TOL:
                result[-1].x = pe.x
            if abs(result[-1].y - pe.y) < TOL:
                result[-1].y = pe.y

    return [p.as_tuple() for p in result] + [pts[last_inx].as_tuple()]
