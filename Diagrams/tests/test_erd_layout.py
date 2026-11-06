import os
import unittest

from diagram_tool.adapters import erd_meta_v1 as A
from diagram_tool.core import jsonio
from diagram_tool.core.errors import ValidationError
from diagram_tool.layout import erd_layout as L

from tests.test_erd_adapter import REAL_META, meta


def star_meta(children, extra_parent_rows=0):
    """One parent table with `children` child tables (each child has one FK to the parent)."""
    tables = [{"name": "cha", "kind": "NEW", "columns": [{"name": "c%d" % i, "pg_type": "int"} for i in range(extra_parent_rows)]}]
    rels = []
    for i in range(children):
        tables.append({"name": "con%d" % i, "kind": "REUSE"})
        rels.append({"parent": "cha", "child": "con%d" % i, "fk_column": "cha_id", "parent_card": "1", "child_card": "0..N"})
    return {"schema_version": "1", "tables": tables, "relationships": rels}


def layout_of(data):
    return L.compute_layout(A.parse_erd_meta(data)), A.parse_erd_meta(data)


class GridTest(unittest.TestCase):
    def test_slot_step_and_capacity_match_the_plan_table(self):
        expected = {240: (4, 10), 280: (3, 13), 320: (3, 13), 360: (3, 13), 400: (2, 20), 440: (2, 20),
                    480: (2, 20), 760: (2, 20), 800: (1, 39), 200: (4, 10)}
        for w, (s, cap) in expected.items():
            self.assertEqual((L.slot_step(w), L.capacity(w)), (s, cap), w)

    def test_required_width_cases(self):
        self.assertEqual(L.required_width(200, 0), 200)
        self.assertEqual(L.required_width(200, 11), 400)       # spare 3 -> cap >= 14
        self.assertEqual(L.required_width(200, 14), 400)       # spare 4 -> cap >= 18
        self.assertEqual(L.required_width(200, 20), 800)       # spare 5 -> cap >= 25
        self.assertEqual(L.required_width(200, 38), 800)       # spare 1
        self.assertEqual(L.required_width(440, 5), 440)        # text width already enough
        self.assertEqual(L.required_width(320, 11), 400)
        with self.assertRaises(ValidationError) as ctx:
            L.required_width(200, 39, "big")
        self.assertEqual(str(ctx.exception), "bang big: qua nhieu quan he tren mot mat (39, toi da 38)")
        with self.assertRaises(ValidationError) as ctx:
            L.loop_slots(56, 1, "tiny")
        self.assertIn("tiny", str(ctx.exception))

    def test_loop_slots_keep_ports_on_the_tenth_grid(self):
        for rows in range(1, 12):
            h = 30 + 26 * rows
            for index in range(3):
                try:
                    ke, kn = L.loop_slots(h, index)
                except ValidationError:
                    continue
                for k in (ke, kn):
                    y = k * h / 40.0
                    self.assertAlmostEqual(y * 10, round(y * 10), places=9, msg=(rows, index, k))
                self.assertGreaterEqual((kn - ke) * h / 40.0, 20)
        self.assertEqual(L.loop_slots(56, 0), (15, 30))     # one-row table: one loop fits (21 px and 42 px)
        with self.assertRaises(ValidationError):
            L.loop_slots(56, 1)                              # a second loop does not


class StarTest(unittest.TestCase):
    def test_widths_follow_the_port_count(self):
        for children, want in ((11, 400), (14, 400), (20, 800), (38, 800)):
            layout, _ = layout_of(star_meta(children))
            self.assertEqual(layout["tables"]["cha"]["w"], want, children)
            ks = sorted(p["upper"]["k"] for p in layout["ports"].values())
            step = L.slot_step(want)
            self.assertEqual(len(ks), children)
            self.assertTrue(all(b - a >= step for a, b in zip(ks, ks[1:])), (children, ks))
            self.assertTrue(1 <= ks[0] and ks[-1] <= 39)

    def test_too_many_children_is_an_error(self):
        with self.assertRaises(ValidationError):
            layout_of(star_meta(39))

    def test_children_sit_below_the_parent_in_one_row(self):
        layout, _ = layout_of(star_meta(5))
        tops = {layout["tables"]["con%d" % i]["y"] for i in range(5)}
        self.assertEqual(len(tops), 1)
        self.assertGreater(tops.pop(), layout["tables"]["cha"]["y"] + layout["tables"]["cha"]["h"])


def check_layout(test, layout, model):
    tables = layout["tables"]
    # integers, grid, top alignment
    for name, t in tables.items():
        test.assertIsInstance(t["x"], int)
        test.assertIsInstance(t["y"], int)
        test.assertEqual(t["w"] % 40, 0)
        test.assertTrue(200 <= t["w"] <= 800)
        test.assertGreaterEqual(t["x"], 0)
    by_layer = {}
    for name, t in tables.items():
        by_layer.setdefault(t["layer"], set()).add(t["y"])
    for ys in by_layer.values():
        test.assertEqual(len(ys), 1)
    # items in a layer never overlap (tables and lanes), minimal gaps respected
    for row in layout["items"]:
        for a, b in zip(row, row[1:]):
            gap = b["left"] - (a["left"] + a["width"])
            need = L.LANE_GAP if (a["kind"] == "lane" or b["kind"] == "lane") else L.TABLE_GAP
            test.assertGreaterEqual(gap, need, (a, b))
    # layers go downwards without overlapping
    layers = layout["layers"]
    for a, b in zip(layers, layers[1:]):
        test.assertGreaterEqual(b["y"], a["y"] + a["height"] + 48)
    # ports
    for ri, pair in layout["ports"].items():
        for side, face in (("upper", "bottom"), ("lower", "top")):
            p = pair[side]
            t = tables[p["table"]]
            test.assertEqual(p["face"], face)
            test.assertTrue(1 <= p["k"] <= 39)
            test.assertEqual(p["x"], t["x"] + p["k"] * (t["w"] // 40))
            test.assertTrue(t["x"] < p["x"] < t["x"] + t["w"])
    per_face = {}
    for ri, pair in layout["ports"].items():
        for side in ("upper", "lower"):
            p = pair[side]
            per_face.setdefault((p["table"], p["face"]), []).append(p["k"])
    for (name, face), ks in per_face.items():
        ks.sort()
        step = L.slot_step(tables[name]["w"])
        test.assertTrue(all(b - a >= step for a, b in zip(ks, ks[1:])), (name, face, ks))
        test.assertLessEqual(len(ks), L.capacity(tables[name]["w"]))
    # every non-loop relation has a chain from its upper to its lower table
    index = {t["name"]: i for i, t in enumerate(model["tables"])}
    for ri, ch in layout["chains"].items():
        r = model["relations"][ri]
        ends = (index[r["child"]], index[r["parent"]]) if ch["flipped"] else (index[r["parent"]], index[r["child"]])
        test.assertEqual((ch["nodes"][0], ch["nodes"][-1]), ends)
    lanes = set(layout["lanes"])
    for ch in layout["chains"].values():
        for d in ch["nodes"][1:-1]:
            test.assertIn(d, lanes)
            test.assertGreaterEqual(d, len(model["tables"]))


class SyntheticLayoutTest(unittest.TestCase):
    def data(self):
        d = meta()
        d["relationships"] = [r for r in d["relationships"] if r["parent"] != r["child"]]
        return d

    def test_invariants_without_loops(self):
        layout, model = layout_of(self.data())
        check_layout(self, layout, model)
        self.assertEqual(layout["loops"], {})

    def test_self_loop_slots_are_reserved(self):
        layout, model = layout_of(meta())
        self.assertEqual(len(layout["loops"]), 1)
        loop = list(layout["loops"].values())[0]
        t = layout["tables"][loop["table"]]
        for k in (loop["k_exit"], loop["k_entry"]):
            y = k * t["h"] / 40.0
            self.assertAlmostEqual(y * 10, round(y * 10), places=9)
        for row in layout["items"]:        # the item right of a table with a loop keeps >= 100 px
            for a, b in zip(row, row[1:]):
                if a["kind"] == "table" and model["tables"][a["id"]]["name"] == loop["table"]:
                    self.assertGreaterEqual(b["left"] - (a["left"] + a["width"]), L.LOOP_GAP)
        check_layout(self, layout, model)

    def test_more_than_three_loops_rejected(self):
        d = self.data()
        for i in range(4):
            d["relationships"].append({"parent": "ban_quan_ly", "child": "ban_quan_ly", "fk_column": "x%d" % i,
                                       "parent_card": "0..1", "child_card": "0..N"})
        with self.assertRaises(ValidationError):
            layout_of(d)

    def test_disconnected_components_sit_side_by_side(self):
        d = {"schema_version": "1", "tables": [
            {"name": "a", "kind": "REUSE"}, {"name": "b", "kind": "REUSE"},
            {"name": "c", "kind": "REUSE"}, {"name": "d", "kind": "REUSE"}, {"name": "iso", "kind": "NEW"}],
            "relationships": [
                {"parent": "a", "child": "b", "fk_column": "a_id", "parent_card": "1", "child_card": "0..N"},
                {"parent": "c", "child": "d", "fk_column": "c_id", "parent_card": "1", "child_card": "0..N"}]}
        layout, model = layout_of(d)
        check_layout(self, layout, model)
        self.assertEqual(len(layout["components"]), 3)
        spans = {}
        for name, t in layout["tables"].items():
            lo, hi = spans.get(t["component"], (10 ** 9, -1))
            spans[t["component"]] = (min(lo, t["x"]), max(hi, t["x"] + t["w"]))
        ordered = [spans[c] for c in sorted(spans)]
        for (lo1, hi1), (lo2, hi2) in zip(ordered, ordered[1:]):
            self.assertGreaterEqual(lo2 - hi1, L.COMPONENT_GAP)

    def test_long_edge_gets_lanes_between_tables(self):
        d = {"schema_version": "1", "tables": [{"name": n, "kind": "REUSE"} for n in "abcd"],
             "relationships": [
                 {"parent": "a", "child": "b", "fk_column": "a_id", "parent_card": "1", "child_card": "0..N"},
                 {"parent": "b", "child": "c", "fk_column": "b_id", "parent_card": "1", "child_card": "0..N"},
                 {"parent": "c", "child": "d", "fk_column": "c_id", "parent_card": "1", "child_card": "0..N"},
                 {"parent": "a", "child": "d", "fk_column": "a2_id", "parent_card": "1", "child_card": "0..N"}]}
        layout, model = layout_of(d)
        check_layout(self, layout, model)
        self.assertEqual(len(layout["lanes"]), 2)
        for lane in layout["lanes"].values():
            row = layout["items"][lane["layer"]]
            lane_item = [it for it in row if it["id"] in layout["lanes"] and layout["lanes"][it["id"]] is lane][0]
            for it in row:
                if it is not lane_item:
                    self.assertTrue(it["left"] + it["width"] <= lane_item["left"] or lane_item["left"] + lane_item["width"] <= it["left"])

    def test_deterministic(self):
        d = self.data()
        self.assertEqual(layout_of(d)[0], layout_of(d)[0])

    def test_chain_is_vertically_aligned(self):
        d = {"schema_version": "1", "tables": [{"name": n, "kind": "REUSE"} for n in "abc"],
             "relationships": [
                 {"parent": "a", "child": "b", "fk_column": "a_id", "parent_card": "1", "child_card": "0..N"},
                 {"parent": "b", "child": "c", "fk_column": "b_id", "parent_card": "1", "child_card": "0..N"}]}
        layout, _ = layout_of(d)
        centres = {n: layout["tables"][n]["x"] + layout["tables"][n]["w"] / 2 for n in "abc"}
        self.assertEqual(centres["a"], centres["b"])
        self.assertEqual(centres["b"], centres["c"])
        # the straight chain gets ports in the same column
        for pair in layout["ports"].values():
            self.assertEqual(pair["upper"]["x"], pair["lower"]["x"])

    def test_lanes_outweigh_busy_tables(self):
        # the table with many neighbours must not push the lane of a long edge sideways
        children = ["c%d" % i for i in range(10)]
        tables = [{"name": n, "kind": "REUSE"} for n in ["top", "hub", "bottom"] + children]
        rels = [{"parent": "top", "child": "hub", "fk_column": "t", "parent_card": "1", "child_card": "0..N"},
                {"parent": "hub", "child": "bottom", "fk_column": "h", "parent_card": "1", "child_card": "0..N"},
                {"parent": "top", "child": "bottom", "fk_column": "t2", "parent_card": "1", "child_card": "0..N"}]
        rels += [{"parent": "hub", "child": c, "fk_column": "h", "parent_card": "1", "child_card": "0..N"} for c in children]
        layout, model = layout_of({"schema_version": "1", "tables": tables, "relationships": rels})
        check_layout(self, layout, model)
        (lane,) = layout["lanes"].values()
        top, hub = layout["tables"]["top"], layout["tables"]["hub"]
        self.assertEqual(lane["layer"], hub["layer"])
        # lane and top table both want to sit above each other: the heavy lane stays close to `top`
        # (within the width of the hub row, whose 10 children pull the hub itself far away)
        lane_to_top = abs(lane["x"] - (top["x"] + top["w"] / 2))
        hub_to_top = abs(hub["x"] + hub["w"] / 2 - (top["x"] + top["w"] / 2))
        self.assertLessEqual(lane_to_top, hub_to_top + hub["w"])

    def test_layer_height_covers_every_table(self):
        layout, model = layout_of(self.data())
        for name, t in layout["tables"].items():
            self.assertLessEqual(t["h"], layout["layers"][t["layer"]]["height"])


@unittest.skipUnless(os.path.exists(REAL_META), "real erd_mau_02.meta.json not available")
class RealDataLayoutTest(unittest.TestCase):
    def test_real_data(self):
        model = A.parse_erd_meta(jsonio.load_file(REAL_META))
        layout = L.compute_layout(model)
        check_layout(self, layout, model)
        self.assertEqual(len(layout["tables"]), 18)
        self.assertEqual(len(layout["chains"]), 32)
        tables = layout["tables"]
        self.assertLess(tables["khu_tap_trung"]["layer"], tables["co_so"]["layer"])
        # the two FKs between the same pair keep separate chains and separate ports
        idx = {r["id"]: i for i, r in enumerate(model["relations"])}
        a = layout["ports"][idx["rel.bao_cao_bql_co_so_kcn.bao_cao_id"]]
        b = layout["ports"][idx["rel.bao_cao_bql_co_so_kcn.bao_cao_nguon_id"]]
        self.assertNotEqual(a["lower"]["k"], b["lower"]["k"])
        bc = tables["bao_cao_moi_truong"]
        n_bottom = sum(1 for p in layout["ports"].values() if p["upper"]["table"] == "bao_cao_moi_truong")
        self.assertGreaterEqual(n_bottom, 8)
        self.assertGreaterEqual(L.capacity(bc["w"]), n_bottom + 2)
        for name, t in tables.items():           # every table holds its ports plus spare room
            used = max(sum(1 for p in layout["ports"].values() if p[s]["table"] == name and p[s]["face"] == f)
                       for s, f in (("upper", "bottom"), ("lower", "top")))
            self.assertGreaterEqual(L.capacity(t["w"]), used + 2, name)
        self.assertEqual(L.compute_layout(model), layout)


if __name__ == "__main__":
    unittest.main()
