"""ERD layout, part 1 (plan g1_erd_plan.md section 5, Step 4/6 = "4a"):
sizes, layer assignment, ordering, x/y coordinates and the INITIAL port slots.

compute_layout(model) -> layout dict (see the end of this docstring). Conflict resolution on the
port grid, lane snapping, tracks and routing belong to erd_route (Step 5/6).

Grid (plan 5.6): table x is an integer, w a multiple of 40, port slots k/40 (k = 1..39) so a
port x is the integer x + k*(w//40). Two ports on a face are at least `slot_step(w)` slots
(>= 20 px) apart; `capacity(w)` slots fit on a face.

layout = {
  "tables":  {name: {"x", "y", "w", "h", "layer", "component", "text_width"}},
  "layers":  [{"y", "height", "gap_below"}...]   (y is top-aligned; gap_below is provisional:
                                                  48 + 14 * pieces, Step 5 recomputes it from tracks),
  "items":   [[{"id", "kind" ("table"|"lane"), "left", "width"}...] per layer, left to right, all components],
  "lanes":   {lane id: {"layer", "x" (centre)}},
  "chains":  {relation index: {"nodes": [ids, upper to lower], "flipped": bool}},   (no self-loops)
  "ports":   {relation index: {"upper": {"table", "face": "bottom", "k", "x"},
                               "lower": {"table", "face": "top", "k", "x"}}},
  "loops":   {relation index: {"table", "index", "k_exit", "k_entry"}},
  "components": [[table names]...]
}
Table ids inside chains/items are table indices (model order); lane ids start at len(tables).
"""

import math

from ..adapters.erd_meta_v1 import TOP_MARGIN
from ..algo.layering import assign_layers
from ..algo.ordering import order_layers
from ..core import schema as S
from ..core.errors import ValidationError

MAX_WIDTH = 800
MAX_FACE_PORTS = 38
LANE_WIDTH = 24
TABLE_GAP = 60
LANE_GAP = 24
LOOP_GAP = 100            # room right of a table with self-loops (strip of 60 px stays free of lanes)
MAX_LOOPS = 3
COMPONENT_GAP = 120
LEFT_MARGIN = 40
GAP_BASE = 48
TRACK_PITCH = 14
PASSES = 12


# ---- port grid ---------------------------------------------------------------------------

def slot_step(w):
    """Slots between two ports of one face so they are >= 20 px apart."""
    p = w // 40
    return -(-20 // p)


def capacity(w):
    return 38 // slot_step(w) + 1


def required_width(text_width, n, name="?"):
    """Smallest multiple of 40 >= text_width that holds `n` ports plus spare room (plan 5.6)."""
    spare = min(max(2, -(-n // 4)), 39 - n)
    if spare < 1:
        raise ValidationError("bang %s: qua nhieu quan he tren mot mat (%d, toi da %d)" % (name, n, MAX_FACE_PORTS))
    w = text_width
    while w <= MAX_WIDTH:
        if capacity(w) >= n + spare:
            return w
        w += 40
    raise ValidationError("table %s: cannot fit %d ports on a face" % (name, n))


def table_height(table):
    return S.TABLE_START_SIZE + S.TABLE_ROW_H * len(table["rows"])


def loop_slots(h, index, name="?"):
    """(k_exit, k_entry) on the right face for the index-th self-loop of a table of height h.

    y = table.y + k*h/40 must have at most one decimal: with an odd (15 + 13n) numerator k has to
    be even. Slots are `s` apart (>= 20 px).
    """
    slot_px = h / 40.0
    unit = 4 // math.gcd(4, h)          # k must be a multiple of `unit` so that k*h/4 is an integer
    s = unit
    while s * slot_px < 20:
        s += unit
    if 2 * (index + 1) * s > 39:
        raise ValidationError("bang %s: qua thap de co %d quan he tu tro" % (name, index + 1))
    return s * (2 * index + 1), s * (2 * index + 2)


# ---- isotonic regression (x placement within a layer) -----------------------------------

def _isotonic(values, weights):
    blocks = []
    for v, w in zip(values, weights):
        blocks.append([v * w, w, 1])
        while len(blocks) > 1 and blocks[-2][0] * blocks[-1][1] > blocks[-1][0] * blocks[-2][1]:
            b = blocks.pop()
            blocks[-1][0] += b[0]
            blocks[-1][1] += b[1]
            blocks[-1][2] += b[2]
    out = []
    for total, weight, count in blocks:
        out += [total / weight] * count
    return out


# ---- main --------------------------------------------------------------------------------

def compute_layout(model):
    tables = model["tables"]
    rels = model["relations"]
    n = len(tables)
    index = {t["name"]: i for i, t in enumerate(tables)}

    layered = assign_layers(n, [(index[r["parent"]], index[r["child"]], r["weight"]) for r in rels])
    rank, flips = layered["rank"], layered["reversed"]

    oriented = []                    # (upper, lower, weight, relation index)
    loops = {}
    loop_count = {}
    for i, r in enumerate(rels):
        a, b = index[r["parent"]], index[r["child"]]
        if a == b:
            k = loop_count.get(a, 0)
            if k >= MAX_LOOPS:
                raise ValidationError("table %s: more than %d self-referencing relations" % (r["parent"], MAX_LOOPS))
            loop_count[a] = k + 1
            loops[i] = {"table": r["parent"], "index": k}
            continue
        if flips[i]:
            a, b = b, a
        oriented.append((a, b, r["weight"], i))

    # ---- ordering per component, dummy ids unique across components ----
    next_dummy = n
    comps = layered["components"]
    comp_layers = []                 # per component: list of layers (ids)
    chains = {}
    flipped = {i: flips[i] for _, _, _, i in oriented}
    for members in comps:
        member_set = set(members)
        local = [e for e in oriented if e[0] in member_set]
        res = order_layers(members, dict(enumerate(rank)), [(u, v, w) for u, v, w, _ in local],
                           first_dummy_id=next_dummy)
        next_dummy += res["dummies"]
        for (u, v, w, ri), chain in zip(local, res["chains"]):
            chains[ri] = {"nodes": chain, "flipped": flipped[ri]}
        comp_layers.append(res["layers"])

    # ---- face port counts -> final widths ----
    top_count = [0] * n
    bottom_count = [0] * n
    for ch in chains.values():
        bottom_count[ch["nodes"][0]] += 1
        top_count[ch["nodes"][-1]] += 1
    width = {}
    for i, t in enumerate(tables):
        width[i] = required_width(t["text_width"], max(top_count[i], bottom_count[i]), t["name"])
    height = {i: table_height(t) for i, t in enumerate(tables)}
    has_loop = {i for i in loop_count}

    # ---- x per component ----
    # links between adjacent layers
    up = {}
    down = {}
    for ch in chains.values():
        for a, b in zip(ch["nodes"], ch["nodes"][1:]):
            down.setdefault(a, []).append(b)
            up.setdefault(b, []).append(a)

    def item_width(x):
        return width[x] if x < n else LANE_WIDTH

    def gap_after(x, y):
        if x < n and x in has_loop:
            return LOOP_GAP
        if x < n and y < n:
            return TABLE_GAP
        return LANE_GAP

    left = {}
    items_by_comp = []
    origin = LEFT_MARGIN
    for layers in comp_layers:
        pos = {}
        for layer in layers:
            cursor = 0
            for j, x in enumerate(layer):
                pos[x] = float(cursor)
                nxt = layer[j + 1] if j + 1 < len(layer) else x
                cursor += item_width(x) + gap_after(x, nxt)
        table_weight = {x: 1.0 + len(up.get(x, [])) + len(down.get(x, []))
                        for layer in layers for x in layer if x < n}
        lane_weight = 2.0 + max(table_weight.values(), default=0.0)     # lanes always outweigh tables
        weight = {x: (lane_weight if x >= n else table_weight[x]) for layer in layers for x in layer}

        def solve(layer, neighbours):
            m = len(layer)
            offsets = []
            acc = 0.0
            for j, x in enumerate(layer):
                offsets.append(acc)
                nxt = layer[j + 1] if j + 1 < m else x
                acc += item_width(x) + gap_after(x, nxt)
            values = []
            for j, x in enumerate(layer):
                ns = neighbours.get(x, [])
                if ns:
                    desired = sum(pos[y] + item_width(y) / 2.0 for y in ns) / len(ns) - item_width(x) / 2.0
                else:
                    desired = pos[x]
                values.append(desired - offsets[j])
            solved = _isotonic(values, [weight[x] for x in layer])
            for j, x in enumerate(layer):
                pos[x] = solved[j] + offsets[j]

        for _ in range(PASSES):
            for li in range(1, len(layers)):
                solve(layers[li], up)
            for li in range(len(layers) - 2, -1, -1):
                solve(layers[li], down)
        low = min(pos.values()) if pos else 0.0
        comp_left = {}
        for layer in layers:
            prev_end = None
            prev = None
            for x in layer:
                v = int(round(pos[x] - low))
                if prev is not None:
                    v = max(v, prev_end + gap_after(prev, x))
                comp_left[x] = v
                prev, prev_end = x, v + item_width(x)
        right = max((comp_left[x] + item_width(x) for x in comp_left), default=0)
        for x, v in comp_left.items():
            left[x] = v + origin
        items_by_comp.append(layers)
        origin += right + COMPONENT_GAP

    # ---- y per layer (shared by all components, tops aligned) ----
    depth = max((len(layers) for layers in comp_layers), default=0)
    layer_h = [0] * depth
    for i in range(n):
        layer_h[rank[i]] = max(layer_h[rank[i]], height[i])
    layer_of_item = {}
    for layers in comp_layers:
        for li, layer in enumerate(layers):
            for x in layer:
                layer_of_item[x] = li
    pieces = [0] * max(depth - 1, 0)
    for ch in chains.values():
        for a in ch["nodes"][:-1]:
            pieces[layer_of_item[a]] += 1
    layers_out = []
    y = TOP_MARGIN
    for li in range(depth):
        h = layer_h[li] if layer_h[li] else 40
        gap = GAP_BASE + TRACK_PITCH * pieces[li] if li < depth - 1 else 0
        layers_out.append({"y": y, "height": h, "gap_below": gap})
        y += h + gap

    items = [[] for _ in range(depth)]
    lanes = {}
    for layers in items_by_comp:
        for li, layer in enumerate(layers):
            for x in layer:
                kind = "table" if x < n else "lane"
                items[li].append({"id": x, "kind": kind, "left": left[x], "width": item_width(x)})
                if kind == "lane":
                    lanes[x] = {"layer": li, "x": left[x] + LANE_WIDTH // 2}
    for row in items:
        row.sort(key=lambda it: it["left"])

    tables_out = {}
    for i, t in enumerate(tables):
        comp_index = next(ci for ci, members in enumerate(comps) if i in members)
        tables_out[t["name"]] = {"x": left[i], "y": layers_out[rank[i]]["y"], "w": width[i], "h": height[i],
                                 "layer": rank[i], "component": comp_index, "text_width": t["text_width"]}

    # ---- initial port slots ----
    def centre(x):
        return left[x] + item_width(x) / 2.0

    ports = {ri: {} for ri in chains}
    faces = {}        # (table index, face) -> list of (target centre, relation index, side)
    for ri, ch in chains.items():
        nodes = ch["nodes"]
        faces.setdefault((nodes[0], "bottom"), []).append((centre(nodes[1]), ri, "upper"))
        faces.setdefault((nodes[-1], "top"), []).append((centre(nodes[-2]), ri, "lower"))
    for (t, face), pieces_here in sorted(faces.items()):
        pieces_here.sort()
        w = width[t]
        p = w // 40
        s = slot_step(w)
        m = len(pieces_here)
        ks = [min(39, max(1, int(round((target - left[t]) / p)))) for target, _, _ in pieces_here]
        for j in range(m):                       # forward: keep >= s apart
            lo = 1 if j == 0 else ks[j - 1] + s
            ks[j] = max(ks[j], lo)
        for j in range(m - 1, -1, -1):           # backward: stay inside 1..39
            hi = 39 if j == m - 1 else ks[j + 1] - s
            ks[j] = min(ks[j], hi)
        for j in range(m):                       # backward may undershoot slot 1: repair forward once more
            lo = 1 if j == 0 else ks[j - 1] + s
            ks[j] = max(ks[j], lo)
        for (target, ri, side), k in zip(pieces_here, ks):
            ports[ri][side] = {"table": tables[t]["name"], "face": face, "k": k, "x": left[t] + k * p}
    loops_out = {}
    for ri, info in loops.items():
        k_exit, k_entry = loop_slots(height[index[info["table"]]], info["index"], info["table"])
        loops_out[ri] = {"table": info["table"], "index": info["index"], "k_exit": k_exit, "k_entry": k_entry}

    return {"tables": tables_out, "layers": layers_out, "items": items, "lanes": lanes, "chains": chains,
            "ports": ports, "loops": loops_out,
            "components": [[tables[i]["name"] for i in members] for members in comps]}
