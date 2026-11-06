import copy
import hashlib
import os
import random
import subprocess
import sys
import time
import unittest

from diagram_tool.adapters import erd_meta_v1 as A
from diagram_tool.algo.tracks import assign_tracks
from diagram_tool.core import jsonio
from diagram_tool.core.errors import ValidationError
from diagram_tool.kinds import erd
from diagram_tool.layout import erd_layout as L
from diagram_tool.layout import erd_route as R

from tests import erd_checks as C
import tests.test_emit as test_emit
from tests.test_erd_adapter import REAL_META, meta
from tests.test_erd_layout import star_meta

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REAL_CROSSING_BOUND = 15      # measured on erd_mau_02: 15 crossings, 84 bends (max 8 per edge), 2780 x 4084 px
REAL_BEND_TOTAL_BOUND = 84
REAL_BEND_MAX_BOUND = 8
REAL_LENGTH_BOUND = 25864      # total edge length (Manhattan px)
REAL_WIDTH_BOUND = 2780
REAL_HEIGHT_BOUND = 4084


def random_meta(rng, tables, rels):
    names = ["t%d" % i for i in range(tables)]
    data = {"schema_version": "1", "tables": [
        {"name": n, "kind": rng.choice(("NEW", "EXTEND", "REUSE"))} for n in names], "relationships": []}
    for i in range(rels):
        a, b = rng.sample(names, 2)
        data["relationships"].append({"parent": a, "child": b, "fk_column": "f%d" % i,
                                      "parent_card": rng.choice(("1", "0..1")),
                                      "child_card": rng.choice(("0..N", "0..1", "1..N"))})
    return data


def check_all(test, data):
    model, doc = erd.layout_document(data)
    lines, tables = C.polylines(doc)
    test.assertEqual(C.overlapping_segments(lines), [])
    test.assertEqual(C.segments_through_tables(lines, tables), [])
    clearance = C.min_clearance(lines, tables)
    if clearance is not None:
        test.assertGreaterEqual(clearance, 8)
    names = list(tables)
    for i, a in enumerate(names):          # tables never overlap
        for b in names[i + 1:]:
            xa, ya, wa, ha = tables[a]
            xb, yb, wb, hb = tables[b]
            test.assertFalse(xa < xb + wb and xb < xa + wa and ya < yb + hb and yb < ya + ha, (a, b))
    loops = {r["id"] for r in model["relations"] if r["loop"]}
    for eid, (first, last) in C.stub_lengths(lines).items():
        if eid not in loops:
            test.assertGreaterEqual(first, 24, eid)
            test.assertGreaterEqual(last, 24, eid)
    # ports after repair: on the grid, >= 20 px apart on each face
    routed = R.route_layout(model, L.compute_layout(model))
    per_face = {}
    for ri, pair in routed["ports"].items():
        for side in ("upper", "lower"):
            p = pair[side]
            w = routed["widths"][p["table"]]
            test.assertEqual(p["x"], routed["positions"][p["table"]][0] + p["k"] * (w // 40))
            per_face.setdefault((p["table"], p["face"]), []).append(p["x"])
    for key, xs_ in per_face.items():
        xs_.sort()
        test.assertTrue(all(b - a >= 20 for a, b in zip(xs_, xs_[1:])), (key, xs_))
    xml, _ = erd.to_drawio(data)
    pages = test_emit.read_pages(xml)
    test_emit.EdgeSimulationTest("test_every_routed_edge").check_page(pages[0])
    return model, doc, lines, tables


class TracksTest(unittest.TestCase):
    def test_empty_and_single(self):
        self.assertEqual(assign_tracks([]), [])
        self.assertEqual(assign_tracks([(10, 50)]), [0])

    def test_overlapping_runs_get_different_tracks(self):
        ranks = assign_tracks([(10, 100), (50, 150), (80, 120)])
        self.assertEqual(len(set(ranks)), 3)

    def test_disjoint_runs_share_a_track(self):
        self.assertEqual(assign_tracks([(10, 20), (40, 60), (80, 100)]), [0, 0, 0])

    def test_touching_intervals_count_as_overlapping(self):
        a, b = assign_tracks([(10, 50), (50 + 1, 90)]), assign_tracks([(10, 50), (50, 90)])
        self.assertEqual(a, [0, 0])
        self.assertNotEqual(b[0], b[1])

    def test_crossing_minimisation_orients_the_pair(self):
        # P goes right (10 -> 60), Q goes left (70 -> 20): intervals overlap; whichever is above, exactly
        # the cheaper orientation is chosen
        p, q = (10, 60), (70, 20)
        ranks = assign_tracks([p, q])
        above = p if ranks[0] < ranks[1] else q
        below = q if above is p else p
        from diagram_tool.algo.tracks import _crossings
        self.assertLessEqual(_crossings(above, below), _crossings(below, above))

    def test_no_two_overlapping_pieces_share_a_track(self):
        rng = random.Random(5)
        for _ in range(100):
            m = rng.randint(1, 10)
            xs = rng.sample(range(0, 400, 3), 2 * m)
            pieces = [(xs[2 * i], xs[2 * i + 1]) for i in range(m)]
            ranks = assign_tracks(pieces)
            for i in range(m):
                for j in range(i + 1, m):
                    lo = max(min(pieces[i]), min(pieces[j]))
                    hi = min(max(pieces[i]), max(pieces[j]))
                    if lo <= hi:
                        self.assertNotEqual(ranks[i], ranks[j], pieces)

    def test_deterministic(self):
        pieces = [(10, 100), (50, 150), (80, 120), (200, 220)]
        self.assertEqual(assign_tracks(pieces), assign_tracks(list(pieces)))


def handmade_layout():
    """Parent P above children C1, C2; the port of P->C2 and the lower port of P->C1 share one x."""
    model = A.parse_erd_meta({"schema_version": "1", "tables": [
        {"name": "p", "kind": "REUSE"}, {"name": "c1", "kind": "REUSE"}, {"name": "c2", "kind": "REUSE"}],
        "relationships": [
            {"parent": "p", "child": "c1", "fk_column": "p_id", "parent_card": "1", "child_card": "0..N"},
            {"parent": "p", "child": "c2", "fk_column": "p_id", "parent_card": "1", "child_card": "0..N"}]})
    h = 30 + 26 * 2
    layout = {
        "tables": {"p": {"x": 40, "y": 100, "w": 240, "h": h, "layer": 0, "component": 0, "text_width": 200},
                   "c1": {"x": 40, "y": 300, "w": 240, "h": h, "layer": 1, "component": 0, "text_width": 200},
                   "c2": {"x": 340, "y": 300, "w": 240, "h": h, "layer": 1, "component": 0, "text_width": 200}},
        "layers": [{"y": 100, "height": h, "gap_below": 0}, {"y": 300, "height": h, "gap_below": 0}],
        "items": [[{"id": 0, "kind": "table", "left": 40, "width": 240}],
                  [{"id": 1, "kind": "table", "left": 40, "width": 240}, {"id": 2, "kind": "table", "left": 340, "width": 240}]],
        "lanes": {}, "components": [["p", "c1", "c2"]], "loops": {},
        "chains": {0: {"nodes": [0, 1], "flipped": False}, 1: {"nodes": [0, 2], "flipped": False}},
        "ports": {
            # P->C1: upper k=12 (x = 40 + 72 = 112), lower k=20 (x = 40 + 120 = 160)
            0: {"upper": {"table": "p", "face": "bottom", "k": 12, "x": 112}, "lower": {"table": "c1", "face": "top", "k": 20, "x": 160}},
            # P->C2: upper k=20 (x = 160) coincides with the lower stub of P->C1; lower k=10 (x = 340 + 60 = 400)
            1: {"upper": {"table": "p", "face": "bottom", "k": 20, "x": 160}, "lower": {"table": "c2", "face": "top", "k": 10, "x": 400}},
        },
    }
    return model, layout


def handmade_x_layout():
    """Two parents pA, pB over two children cA, cB; P = pA->cB and Q = pB->cA form a hard cycle:
    x_u(P) == x_l(Q) (112) and x_u(Q) == x_l(P) (400)."""
    model = A.parse_erd_meta({"schema_version": "1", "tables": [
        {"name": n, "kind": "REUSE"} for n in ("pa", "pb", "ca", "cb")],
        "relationships": [
            {"parent": "pa", "child": "cb", "fk_column": "pa_id", "parent_card": "1", "child_card": "0..N"},
            {"parent": "pb", "child": "ca", "fk_column": "pb_id", "parent_card": "1", "child_card": "0..N"}]})
    h = 30 + 26 * 2
    t = lambda x, y, layer: {"x": x, "y": y, "w": 240, "h": h, "layer": layer, "component": 0, "text_width": 200}
    layout = {
        "tables": {"pa": t(40, 100, 0), "pb": t(340, 100, 0), "ca": t(40, 300, 1), "cb": t(340, 300, 1)},
        "layers": [{"y": 100, "height": h, "gap_below": 0}, {"y": 300, "height": h, "gap_below": 0}],
        "items": [[{"id": 0, "kind": "table", "left": 40, "width": 240}, {"id": 1, "kind": "table", "left": 340, "width": 240}],
                  [{"id": 2, "kind": "table", "left": 40, "width": 240}, {"id": 3, "kind": "table", "left": 340, "width": 240}]],
        "lanes": {}, "components": [["pa", "pb", "ca", "cb"]], "loops": {},
        "chains": {0: {"nodes": [0, 3], "flipped": False}, 1: {"nodes": [1, 2], "flipped": False}},
        "ports": {
            0: {"upper": {"table": "pa", "face": "bottom", "k": 12, "x": 112}, "lower": {"table": "cb", "face": "top", "k": 10, "x": 400}},
            1: {"upper": {"table": "pb", "face": "bottom", "k": 10, "x": 400}, "lower": {"table": "ca", "face": "top", "k": 12, "x": 112}},
        },
    }
    return model, layout


class RouterTest(unittest.TestCase):
    def test_hard_cycle_in_both_directions_is_resolved(self):
        model, layout = handmade_x_layout()
        router = R.Router(model, layout)
        self.assertTrue(router.bad(0) and router.bad(1))
        self.assertEqual(router.conflicts_of(0), [1])
        router.resolve()
        self.assertFalse(any(router.bad(i) for i in range(2)))
        xs = [x for i in range(2) for x in router.xs(i)]
        self.assertEqual(len(xs), len(set(xs)))
        routed = R.route_layout(model, layout)
        doc = A.build_raw_document(model, routed["positions"], routed["widths"], routed["routes"])
        lines, tables = C.polylines(doc)
        self.assertEqual(C.overlapping_segments(lines), [])
        self.assertEqual(C.segments_through_tables(lines, tables), [])

    def test_coinciding_stubs_are_repaired(self):
        model, layout = handmade_layout()
        router = R.Router(model, layout)
        self.assertTrue(any(router.bad(i) for i in range(len(router.pieces))))
        router.resolve()
        self.assertFalse(any(router.bad(i) for i in range(len(router.pieces))))
        xs = [x for i in range(len(router.pieces)) for x in router.xs(i)]
        self.assertEqual(len(xs), len(set(xs)))
        for ri, pair in router.ports.items():          # still on the grid, still apart on each face
            for side in ("upper", "lower"):
                p = pair[side]
                t = router.tables[p["table"]]
                self.assertEqual(p["x"], t["x"] + p["k"] * (t["w"] // 40))
                self.assertTrue(1 <= p["k"] <= 39)

    def test_short_runs_are_repaired(self):
        model, layout = handmade_layout()
        layout["ports"][0]["upper"].update(k=12, x=112)
        layout["ports"][0]["lower"].update(k=15, x=130)        # run of 18 px: fine
        layout["ports"][1]["upper"].update(k=30, x=220)
        layout["ports"][1]["lower"].update(k=6, x=376)         # long run: fine
        router = R.Router(model, layout)
        self.assertFalse(any(router.bad(i) for i in range(len(router.pieces))))   # valid start
        router.resolve()
        layout["ports"][0]["lower"].update(k=12 + 1, x=40 + 13 * 6)   # run 6 px < 8 -> repaired
        router = R.Router(model, layout)
        self.assertTrue(router.bad(0))
        router.resolve()
        xu, xl = router.xs(0)
        self.assertTrue(xu == xl or abs(xu - xl) >= R.MIN_RUN)

    def test_straight_pieces_own_their_x(self):
        model, layout = handmade_layout()
        layout["ports"][0]["upper"].update(k=12, x=112)
        layout["ports"][0]["lower"].update(k=12, x=112)        # P->C1 is straight at x = 112
        layout["tables"]["c2"]["x"] = 40                       # (rows overlap: only the predicate matters here)
        layout["ports"][1]["upper"].update(k=20, x=160)
        layout["ports"][1]["lower"].update(k=12, x=112)        # another stub at the same x
        router = R.Router(model, layout)
        self.assertTrue(router.straight(0))
        self.assertEqual(router.conflicts_of(0), [1])
        self.assertTrue(router.bad(0) and router.bad(1))
        router.resolve()
        self.assertFalse(any(router.bad(i) for i in range(len(router.pieces))))
        xs = [x for i in range(len(router.pieces)) for x in router.xs(i)]
        self.assertEqual(len(xs) - len(set(xs)), 1 if router.straight(0) else 0)   # a straight piece lists x twice

    def test_unrepairable_layout_raises(self):
        model, layout = handmade_layout()
        router = R.Router(model, layout)
        router.try_move = lambda ep: False                     # nothing can move
        with self.assertRaises(ValidationError) as ctx:
            router.resolve()
        self.assertIn("khong dinh tuyen duoc", str(ctx.exception))

    def test_route_layout_on_handmade_layout(self):
        model, layout = handmade_layout()
        routed = R.route_layout(model, layout)
        for rid, route in routed["routes"].items():
            self.assertIn("exit", route)
            self.assertIn("entry", route)
        doc = A.build_raw_document(model, routed["positions"], routed["widths"], routed["routes"])
        lines, tables = C.polylines(doc)
        self.assertEqual(C.overlapping_segments(lines), [])
        self.assertEqual(C.segments_through_tables(lines, tables), [])


class PipelineTest(unittest.TestCase):
    def test_synthetic_meta_with_self_loop(self):
        model, doc, lines, tables = check_all(self, meta())
        loop_id = [r["id"] for r in model["relations"] if r["loop"]][0]
        pts = lines[loop_id]
        self.assertEqual(len(pts), 4)
        self.assertEqual(pts[1][0], pts[2][0])                  # vertical run right of the table
        x, y, w, h = tables["ban_quan_ly"]
        self.assertEqual(pts[1][0], x + w + R.LOOP_OFFSET)
        self.assertEqual(pts[0][0], x + w)

    def test_star_with_many_children(self):
        for children in (3, 8, 11, 14, 38):      # 8 = a full face of a 200 px table (cap 10 = 8 + 2 spare)
            model, doc, lines, tables = check_all(self, star_meta(children))
            if children == 8:
                self.assertEqual(tables["cha"][2], 200)

    def test_flipped_relations_swap_the_ports(self):
        data = {"schema_version": "1", "tables": [{"name": "a", "kind": "REUSE"}, {"name": "b", "kind": "REUSE"}],
                "relationships": [
                    {"parent": "a", "child": "b", "fk_column": "a_id", "parent_card": "1", "child_card": "0..N"},
                    {"parent": "b", "child": "a", "fk_column": "b_id", "parent_card": "0..1", "child_card": "0..1"}]}
        model, doc, lines, tables = check_all(self, data)
        edges = {c["id"]: c for c in doc["pages"][0]["cells"] if c["type"] == "edge"}
        ok = edges["rel.b.a_id"]
        flipped = edges["rel.a.b_id"]                    # parent b is the LOWER end: source exits through its top face
        self.assertEqual((ok["exit"]["y"], ok["entry"]["y"]), (1, 0))
        self.assertEqual((flipped["exit"]["y"], flipped["entry"]["y"]), (0, 1))
        self.assertEqual((flipped["source"], flipped["target"]), ("b", "a"))

    def test_disjoint_components(self):
        data = {"schema_version": "1", "tables": [{"name": n, "kind": "NEW"} for n in ("a", "b", "c", "d", "e")],
                "relationships": [
                    {"parent": "a", "child": "b", "fk_column": "a_id", "parent_card": "1", "child_card": "0..N"},
                    {"parent": "c", "child": "d", "fk_column": "c_id", "parent_card": "1", "child_card": "0..N"}]}
        check_all(self, data)

    def test_random_graphs(self):
        rng = random.Random(2026)
        for _ in range(25):
            data = random_meta(rng, rng.randint(3, 14), rng.randint(2, 22))
            check_all(self, data)

    def test_performance_60_tables(self):
        rng = random.Random(1)
        data = random_meta(rng, 60, 90)
        start = time.time()
        erd.to_drawio(data)
        self.assertLess(time.time() - start, 5.0)

    def test_deterministic_across_hash_seeds(self):
        code = ("import hashlib, sys\n"
                "from tests.test_erd_adapter import meta\n"
                "from diagram_tool.kinds import erd\n"
                "d = meta()\n"
                "print(hashlib.sha256(erd.to_drawio(d)[0].encode('utf-8')).hexdigest())\n")
        outs = set()
        for seed in ("0", "1", "4242", "random"):
            env = dict(os.environ, PYTHONHASHSEED=seed, PYTHONDONTWRITEBYTECODE="1")
            proc = subprocess.run([sys.executable, "-B", "-c", code], cwd=ROOT, env=env, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE)
            self.assertEqual(proc.returncode, 0, proc.stderr.decode("utf-8", "replace"))
            outs.add(proc.stdout)
        self.assertEqual(len(outs), 1)

    def test_input_not_mutated(self):
        data = meta()
        snapshot = copy.deepcopy(data)
        erd.to_drawio(data)
        self.assertEqual(data, snapshot)


@unittest.skipUnless(os.path.exists(REAL_META), "real erd_mau_02.meta.json not available")
class RealDataRouteTest(unittest.TestCase):
    def test_real_data_metrics(self):
        data = jsonio.load_file(REAL_META)
        model, doc, lines, tables = check_all(self, data)
        self.assertEqual(len(lines), 32)
        crossings = C.crossings(lines)
        self.assertLessEqual(crossings, REAL_CROSSING_BOUND)
        bends = [len(p) - 2 for p in lines.values()]
        self.assertLessEqual(sum(bends), REAL_BEND_TOTAL_BOUND)
        self.assertLessEqual(max(bends), REAL_BEND_MAX_BOUND)
        length = sum(abs(a[0] - b[0]) + abs(a[1] - b[1]) for p in lines.values() for a, b in zip(p, p[1:]))
        self.assertLessEqual(length, REAL_LENGTH_BOUND)
        self.assertLessEqual(max(x + w for x, y, w, h in tables.values()), REAL_WIDTH_BOUND)
        self.assertLessEqual(max(y + h for x, y, w, h in tables.values()), REAL_HEIGHT_BOUND)
        self.assertGreaterEqual(C.min_clearance(lines, tables), 24)
        # the flipped FK between co_so and khu_tap_trung: source = parent co_so leaves through its top face
        edges = {c["id"]: c for c in doc["pages"][0]["cells"] if c["type"] == "edge"}
        e = edges["rel.khu_tap_trung.co_so_ha_tang_id"]
        self.assertEqual((e["source"], e["target"]), ("co_so", "khu_tap_trung"))
        self.assertEqual((e["exit"]["y"], e["entry"]["y"]), (0, 1))
        again, _ = erd.to_drawio(data)
        self.assertEqual(erd.to_drawio(data)[0], again)


if __name__ == "__main__":
    unittest.main()
