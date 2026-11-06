"""ERD layout, part 2 (plan g1_erd_plan.md 5.9-5.10, Step 5/6): conflict resolution, tracks, y, routing.

route_layout(model, layout) -> {"positions": {table: (x, y)}, "widths": {table: w},
                                "routes": {relation id: {"exit", "entry", "points"}},
                                "layers": [...], "track_counts": [...]}

Invariant enforced before tracks are assigned (simpler and stronger than the plan's arc rules):
in every gap between two layers the x of all vertical stubs of different pieces are pairwise
different (a straight piece owns its x alone) and every non-straight piece has a horizontal run
of at least MIN_RUN px. Violations are repaired by moving ONE endpoint (a table port to another
slot of its face, or a lane sideways) to the nearest position that strictly lowers the total
violation count of the gaps it touches (violations = short runs + coinciding x per pair of
pieces; a valid piece may become a violation if the total drops, which a two-way "X" cycle
needs). The count is a non-negative integer that drops with every accepted move, so the repair
terminates. If a violation cannot be repaired the call fails with a ValidationError (never a
silent overlap).
"""

import copy

from ..adapters.erd_meta_v1 import TOP_MARGIN
from ..algo.tracks import assign_tracks
from ..core.errors import ValidationError
from . import erd_layout as L

MIN_RUN = 8
TRACK_TOP = 24
TRACK_PITCH = 14
GAP_BASE = 48
LOOP_OFFSET = 30
LOOP_STEP = 14


def _ratio(k):
    return round(k / 40.0, 4)


class Router:
    def __init__(self, model, layout):
        self.model = model
        self.layout = copy.deepcopy(layout)
        self.tables = self.layout["tables"]
        self.ports = self.layout["ports"]
        self.lanes = self.layout["lanes"]
        self.names = [t["name"] for t in model["tables"]]
        self.loop_tables = {info["table"] for info in self.layout["loops"].values()}
        self.pieces = []
        self.touch = {}
        for ri in sorted(self.layout["chains"]):
            nodes = self.layout["chains"][ri]["nodes"]
            for j in range(len(nodes) - 1):
                a, b = nodes[j], nodes[j + 1]
                upper = ("port", ri, "upper") if j == 0 else ("lane", a)
                lower = ("port", ri, "lower") if j == len(nodes) - 2 else ("lane", b)
                gap = self.tables[self.names[a]]["layer"] if a < len(self.names) else self.lanes[a]["layer"]
                self.pieces.append({"ri": ri, "j": j, "gap": gap, "upper": upper, "lower": lower})
        self.by_gap = {}
        for i, p in enumerate(self.pieces):
            self.by_gap.setdefault(p["gap"], []).append(i)
            self.touch.setdefault(p["upper"], []).append(i)
            self.touch.setdefault(p["lower"], []).append(i)

    # ---- positions ----
    def x_of(self, ep):
        if ep[0] == "port":
            return self.ports[ep[1]][ep[2]]["x"]
        return self.lanes[ep[1]]["x"]

    def xs(self, i):
        p = self.pieces[i]
        return self.x_of(p["upper"]), self.x_of(p["lower"])

    def straight(self, i):
        xu, xl = self.xs(i)
        return xu == xl

    def conflicts_of(self, i):
        """Other pieces of the gap whose stubs coincide with a stub of piece i."""
        xu, xl = self.xs(i)
        mine = {xu, xl}
        out = []
        for q in self.by_gap[self.pieces[i]["gap"]]:
            if q != i and mine & set(self.xs(q)):
                out.append(q)
        return out

    def bad(self, i):
        xu, xl = self.xs(i)
        if xu != xl and abs(xu - xl) < MIN_RUN:
            return True
        return bool(self.conflicts_of(i))

    # ---- candidates ----
    def _port_candidates(self, ep):
        port = self.ports[ep[1]][ep[2]]
        table = self.tables[port["table"]]
        step = L.slot_step(table["w"])
        p = table["w"] // 40
        others = [q["k"] for ri, pair in self.ports.items() for side, q in pair.items()
                  if q["table"] == port["table"] and q["face"] == port["face"] and (ri, side) != (ep[1], ep[2])]
        out = []
        for delta in range(1, 39):
            for k in (port["k"] - delta, port["k"] + delta):
                if 1 <= k <= 39 and all(abs(k - o) >= step for o in others):
                    out.append((k, table["x"] + k * p))
        return out

    def _row(self, lane_id):
        return self.layout["items"][self.lanes[lane_id]["layer"]]

    def _left_of(self, item):
        if item["kind"] == "lane":
            return self.lanes[item["id"]]["x"] - L.LANE_WIDTH // 2
        return self.tables[self.names[item["id"]]]["x"]

    def _lane_range(self, lane_id):
        row = self._row(lane_id)
        pos = next(i for i, it in enumerate(row) if it["id"] == lane_id)
        lo = 0
        if pos > 0:
            prev = row[pos - 1]
            gap = L.LOOP_GAP if (prev["kind"] == "table" and self.names[prev["id"]] in self.loop_tables) else L.LANE_GAP
            lo = self._left_of(prev) + prev["width"] + gap
        hi = self._left_of(row[pos]) + 400
        if pos + 1 < len(row):
            hi = self._left_of(row[pos + 1]) - L.LANE_GAP - L.LANE_WIDTH
        return max(lo, 0), hi

    def _lane_candidates(self, ep):
        lane = self.lanes[ep[1]]
        lo, hi = self._lane_range(ep[1])
        cur = lane["x"] - L.LANE_WIDTH // 2
        out = []
        for delta in range(1, 400):
            for left in (cur - delta, cur + delta):
                if lo <= left <= hi:
                    out.append((left, left + L.LANE_WIDTH // 2))
            if cur - delta < lo and cur + delta > hi:
                break
        return out

    def _set(self, ep, value):
        if ep[0] == "port":
            port = self.ports[ep[1]][ep[2]]
            port["k"], port["x"] = value
        else:
            self.lanes[ep[1]]["x"] = value[1]

    def _get(self, ep):
        if ep[0] == "port":
            port = self.ports[ep[1]][ep[2]]
            return (port["k"], port["x"])
        return (self.lanes[ep[1]]["x"] - L.LANE_WIDTH // 2, self.lanes[ep[1]]["x"])

    def gap_violations(self, gap):
        """Violation count of a gap: short runs plus coincident x between pieces (pairwise)."""
        idxs = self.by_gap[gap]
        total = 0
        sets = []
        for i in idxs:
            xu, xl = self.xs(i)
            if xu != xl and abs(xu - xl) < MIN_RUN:
                total += 1
            sets.append({xu, xl})
        for a in range(len(sets)):
            for b in range(a + 1, len(sets)):
                total += len(sets[a] & sets[b])
        return total

    def total_violations(self):
        return sum(self.gap_violations(g) for g in self.by_gap)

    def try_move(self, ep):
        """Move `ep` to the nearest position that strictly lowers the violation count of its gaps."""
        old = self._get(ep)
        gaps = sorted({self.pieces[i]["gap"] for i in self.touch[ep]})
        before = sum(self.gap_violations(g) for g in gaps)
        cands = self._port_candidates(ep) if ep[0] == "port" else self._lane_candidates(ep)
        for value in cands:
            self._set(ep, value)
            if sum(self.gap_violations(g) for g in gaps) < before:
                return True
        self._set(ep, old)
        return False

    def resolve(self):
        limit = self.total_violations() + len(self.pieces) + 10      # every accepted move lowers the count
        for _ in range(limit):
            bad = [i for i in range(len(self.pieces)) if self.bad(i)]
            if not bad:
                return
            i = bad[0]
            order = [i] + self.conflicts_of(i)
            tried = []
            for q in order:
                piece = self.pieces[q]
                for ep in sorted((piece["upper"], piece["lower"]), key=lambda e: (e[0] != "port", str(e))):
                    if ep not in tried:
                        tried.append(ep)
            if not any(self.try_move(ep) for ep in tried):
                p = self.pieces[i]
                raise ValidationError("khong dinh tuyen duoc ma khong chong doan (quan he %s)"
                                      % self.model["relations"][p["ri"]]["id"])
        raise ValidationError("khong dinh tuyen duoc ma khong chong doan (qua so vong sua)")

    # ---- tracks, y, routes ----
    def tracks(self):
        self.track = {}
        counts = [0] * len(self.layout["layers"])
        for g in sorted(self.by_gap):
            idxs = [i for i in self.by_gap[g] if not self.straight(i)]
            ranks = assign_tracks([self.xs(i) for i in idxs])
            for i, r in zip(idxs, ranks):
                self.track[i] = r
            counts[g] = (max(ranks) + 1) if ranks else 0
        return counts

    def place_layers(self, counts):
        layers = copy.deepcopy(self.layout["layers"])
        y = TOP_MARGIN
        for li, layer in enumerate(layers):
            gap = (GAP_BASE + TRACK_PITCH * counts[li]) if li < len(layers) - 1 else 0
            layer["y"], layer["gap_below"] = y, gap
            y += layer["height"] + gap
        return layers

    def routes(self, layers):
        out = {}
        index = {t["name"]: i for i, t in enumerate(self.model["tables"])}
        by_chain = {}
        for i, p in enumerate(self.pieces):
            by_chain.setdefault(p["ri"], []).append(i)
        for ri, idxs in sorted(by_chain.items()):
            ch = self.layout["chains"][ri]
            first, last = self.ports[ri]["upper"], self.ports[ri]["lower"]
            up_t, low_t = self.tables[first["table"]], self.tables[last["table"]]
            pts = [(first["x"], layers[up_t["layer"]]["y"] + up_t["h"])]
            for i in idxs:
                if i not in self.track:
                    continue
                g = self.pieces[i]["gap"]
                y = layers[g]["y"] + layers[g]["height"] + TRACK_TOP + TRACK_PITCH * self.track[i]
                xu, xl = self.xs(i)
                pts += [(xu, y), (xl, y)]
            pts.append((last["x"], layers[low_t["layer"]]["y"]))
            pts = _simplify(pts)
            start_port, end_port = (first, last)
            if ch["flipped"]:                       # parent is the LOWER end: source = lower
                pts.reverse()
                start_port, end_port = last, first
            rid = self.model["relations"][ri]["id"]
            out[rid] = {
                "exit": {"x": _ratio(start_port["k"]), "y": 1 if start_port["face"] == "bottom" else 0},
                "entry": {"x": _ratio(end_port["k"]), "y": 1 if end_port["face"] == "bottom" else 0},
                "points": [{"x": x, "y": y} for x, y in pts[1:-1]],
            }
        for ri, info in self.layout["loops"].items():
            t = self.tables[info["table"]]
            y0 = layers[t["layer"]]["y"]
            xr = t["x"] + t["w"] + LOOP_OFFSET + LOOP_STEP * info["index"]
            y1 = round(y0 + info["k_exit"] * t["h"] / 40.0, 1)
            y2 = round(y0 + info["k_entry"] * t["h"] / 40.0, 1)
            out[self.model["relations"][ri]["id"]] = {
                "exit": {"x": 1, "y": _ratio(info["k_exit"])}, "entry": {"x": 1, "y": _ratio(info["k_entry"])},
                "points": [{"x": xr, "y": y1}, {"x": xr, "y": y2}]}
        return out


def _simplify(pts):
    """Drop repeated points and points that lie on a straight line between their neighbours."""
    out = []
    for p in pts:
        if out and out[-1] == p:
            continue
        out.append(p)
    changed = True
    while changed:
        changed = False
        for i in range(1, len(out) - 1):
            a, b, c = out[i - 1], out[i], out[i + 1]
            if (a[0] == b[0] == c[0]) or (a[1] == b[1] == c[1]):
                del out[i]
                changed = True
                break
    return out


def route_layout(model, layout):
    router = Router(model, layout)
    router.resolve()
    counts = router.tracks()
    layers = router.place_layers(counts)
    routes = router.routes(layers)
    positions = {name: (t["x"], layers[t["layer"]]["y"]) for name, t in router.tables.items()}
    widths = {name: t["w"] for name, t in router.tables.items()}
    return {"positions": positions, "widths": widths, "routes": routes, "layers": layers,
            "track_counts": counts, "ports": router.ports, "lanes": router.lanes}
