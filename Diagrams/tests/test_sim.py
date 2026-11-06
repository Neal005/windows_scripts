import unittest

from diagram_tool.core import geometry
from diagram_tool.core import schema as S
from diagram_tool.kinds.raw import validate_raw
from diagram_tool.sim.segment_connector import segment_connector
from diagram_tool.sim.stack_layout import stack_layout

from tests.test_validator_raw import base_doc, nested_doc


def pt(x, y):
    return {"x": x, "y": y}


# Blocks used by the route cases: A (100,100,100x40) and B (400,300,100x40).
#   A ports: right (200,120) left (100,120) top (150,100) bottom (150,140)
#   B ports: right (500,320) left (400,320) top (450,300) bottom (450,340)
A_RIGHT, A_LEFT, A_TOP, A_BOTTOM = {"x": 1, "y": 0.5}, {"x": 0, "y": 0.5}, {"x": 0.5, "y": 0}, {"x": 0.5, "y": 1}
ROUTE_CASES = [
    ("1 corner right->top", A_RIGHT, A_TOP, [pt(450, 120)]),
    ("1 corner bottom->left", A_BOTTOM, A_LEFT, [pt(150, 320)]),
    ("2 corners right->right", A_RIGHT, {"x": 1, "y": 0.5}, [pt(550, 120), pt(550, 320)]),
    ("2 corners bottom->bottom", A_BOTTOM, A_BOTTOM, [pt(150, 400), pt(450, 400)]),
    ("3 corners bottom->left", A_BOTTOM, A_LEFT, [pt(150, 200), pt(300, 200), pt(300, 320)]),
    ("4 corners right->left", A_RIGHT, A_LEFT, [pt(250, 120), pt(250, 220), pt(350, 220), pt(350, 320)]),
    ("6 corners staircase right->left", A_RIGHT, A_LEFT,
     [pt(220, 120), pt(220, 160), pt(260, 160), pt(260, 240), pt(300, 240), pt(300, 320)]),
    ("2 corners top->top", A_TOP, A_TOP, [pt(150, 60), pt(450, 60)]),
    ("2 corners left->left", A_LEFT, A_LEFT, [pt(60, 120), pt(60, 320)]),
]


def route_doc(exit_port, entry_port, points):
    return {"schema_version": 1, "kind": "raw", "pages": [{"id": "p", "cells": [
        {"id": "A", "type": "vertex", "x": 100, "y": 100, "w": 100, "h": 40},
        {"id": "B", "type": "vertex", "x": 400, "y": 300, "w": 100, "h": 40},
        {"id": "E", "type": "edge", "source": "A", "target": "B",
         "exit": exit_port, "entry": entry_port, "points": points},
    ]}]}


def sim_for(doc, edge_id):
    """Validate, then route with the draw.io port. Returns (declared_polyline, simulated_polyline)."""
    page = validate_raw(doc).doc["pages"][0]
    by_id = {c["id"]: c for c in page["cells"]}
    edge = by_id[edge_id]
    p0, pn = geometry.edge_endpoints(by_id, edge)
    declared = [p0] + [(p["x"], p["y"]) for p in edge["points"]] + [pn]
    hints = [(p["x"], p["y"]) for p in edge["points"]]
    return declared, segment_connector(p0, pn, hints)


class SegmentConnectorHandTracedTest(unittest.TestCase):
    def test_no_hints_makes_one_bend(self):
        # hint = start, horizontal first: bend at (end.x, start.y)
        self.assertEqual(segment_connector((200, 120), (400, 320), []),
                         [(200, 120), (400, 120), (400, 320)])
        # same y -> straight
        self.assertEqual(segment_connector((0, 50), (100, 50), []), [(0, 50), (100, 50)])

    def test_one_hint(self):
        self.assertEqual(segment_connector((100, 20), (300, 100), [(300, 20)]),
                         [(100, 20), (300, 20), (300, 100)])

    def test_misaligned_first_hint_adds_a_bend(self):
        out = segment_connector((200, 120), (300, 300), [(300, 150)])
        self.assertIn((200, 150), out)  # draw.io inserts a bend: path differs from the declared one
        self.assertNotEqual(out, [(200, 120), (300, 150), (300, 300)])

    def test_points_closer_than_one_pixel_are_dropped(self):
        declared = [(200, 120), (250, 120), (250, 120.4), (400, 120.4)]
        out = segment_connector(declared[0], declared[-1], declared[1:-1])
        self.assertEqual(out, [(200, 120), (250, 120), (400, 120.4)])

    def test_no_hints_keeps_bend_even_if_end_is_within_tolerance(self):
        # `pe` exists only inside the controlHints block in the JS: without hints the final
        # "drop last point inside tolerance" step does not run.
        self.assertEqual(segment_connector((0, 0), (100, 0.5), []), [(0, 0), (100, 0), (100, 0.5)])
        # with hints: pushPoint drops the 0.5 px step and the last hint snaps to the end point's y
        self.assertEqual(segment_connector((0, 0), (100, 0.5), [(50, 0)]), [(0, 0), (50, 0), (100, 0.5)])

    def test_collinear_point_is_dropped_by_pushpoint(self):
        # the case that motivated the validator's "must be a bend" rule
        out = segment_connector((200, 120), (400, 120), [(250, 120), (300, 120)])
        self.assertEqual(out, [(200, 120), (250, 120), (400, 120)])

    def test_diagonal_hints_are_redrawn(self):
        hints = [(250, 120), (300, 170), (300, 300)]
        out = segment_connector((200, 120), (300, 300), hints)
        self.assertNotEqual(out, [(200, 120)] + hints + [(300, 300)])
        self.assertIn((250, 170), out)

    def test_hint_within_tolerance_snaps_to_end_point(self):
        # last hint 0.5 px off the end point's x snaps onto it
        out = segment_connector((100, 100), (300, 200), [(300.5, 100)])
        self.assertEqual(out[-1], (300, 200))
        self.assertIn((300, 100), out)

    def test_rounding_to_tenth(self):
        out = segment_connector((0, 0), (100.04, 60), [(50.04, 0), (50.04, 60)])
        self.assertTrue(all(abs(x * 10 - round(x * 10)) < 1e-9 for p in out for x in p))


class ValidatorAgreesWithSimulationTest(unittest.TestCase):
    """Corner lists the validator accepts give exactly the declared polyline in the port of
    SegmentConnector (both end points fixed). Edges with 0 points go through OrthConnector,
    which is NOT ported (listed as UNVERIFIED in the plan, section 9)."""

    def test_collinear_point_rejected_by_validator(self):
        from diagram_tool.core.errors import ValidationError
        # exit right (200,120) -> entry left of a block at y=120: (250,120),(300,120) are not bends
        doc = {"schema_version": 1, "kind": "raw", "pages": [{"id": "p", "cells": [
            {"id": "A", "type": "vertex", "x": 100, "y": 100, "w": 100, "h": 40},
            {"id": "B", "type": "vertex", "x": 400, "y": 100, "w": 100, "h": 40},
            {"id": "E", "type": "edge", "source": "A", "target": "B", "exit": A_RIGHT, "entry": A_LEFT,
             "points": [pt(250, 120), pt(300, 120)]},
        ]}]}
        with self.assertRaises(ValidationError) as ctx:
            validate_raw(doc)
        self.assertIn("points[0]", str(ctx.exception))
        self.assertIn("not a bend", str(ctx.exception))
        # a single collinear point is rejected too (exit and entry on the same line)
        doc["pages"][0]["cells"][2]["points"] = [pt(300, 120)]
        with self.assertRaises(ValidationError):
            validate_raw(doc)
        # a U-turn (reverses direction on the same line) is rejected as well
        doc["pages"][0]["cells"][2]["points"] = [pt(250, 120), pt(220, 120)]
        with self.assertRaises(ValidationError):
            validate_raw(doc)

    def test_route_cases(self):
        for name, ex, en, points in ROUTE_CASES:
            with self.subTest(name):
                declared, simulated = sim_for(route_doc(ex, en, points), "E")
                self.assertEqual(simulated, declared)

    def test_nested_containers_with_different_origins(self):
        declared, simulated = sim_for(nested_doc(), "E")
        self.assertEqual(simulated, declared)
        self.assertEqual(declared[0], (170, 160))   # X bottom centre in G's frame (G at 50,50; H at 100,100)
        self.assertEqual(declared[-1], (650, 60))   # Y bottom centre in G's frame

    def test_self_loop(self):
        doc = {"schema_version": 1, "kind": "raw", "pages": [{"id": "p", "cells": [
            {"id": "A", "type": "vertex", "x": 100, "y": 100, "w": 100, "h": 40},
            {"id": "L", "type": "edge", "source": "A", "target": "A",
             "exit": {"x": 1, "y": 0.25}, "entry": {"x": 1, "y": 0.75},
             "points": [pt(240, 110), pt(240, 130)]},
        ]}]}
        declared, simulated = sim_for(doc, "L")
        self.assertEqual(declared, [(200, 110), (240, 110), (240, 130), (200, 130)])
        self.assertEqual(simulated, declared)

    def test_base_doc_edge(self):
        declared, simulated = sim_for(base_doc(), "E1")
        self.assertEqual(simulated, declared)

    def test_rejected_inputs_would_be_drawn_differently(self):
        # The validator refuses these; the port shows draw.io would not draw the declared polyline.
        cases = [
            ("misaligned first point", A_RIGHT, A_TOP, [pt(450, 130)]),
            ("diagonal", A_RIGHT, A_LEFT, [pt(250, 120), pt(260, 220), pt(350, 220), pt(350, 320)]),
            ("segment shorter than 1px", A_RIGHT, A_LEFT, [pt(250, 120), pt(250, 120.4), pt(350, 120.4), pt(350, 320)]),
        ]
        for name, ex, en, points in cases:
            with self.subTest(name):
                p0, pn = (200, 120), (450, 300) if en is A_TOP else (400, 320)
                hints = [(p["x"], p["y"]) for p in points]
                out = segment_connector(p0, pn, hints)
                self.assertNotEqual(out, [p0] + hints + [pn])


class StackLayoutTest(unittest.TestCase):
    def test_hand_traced_vertical(self):
        kids = [{"x": 9, "y": 9, "w": 9, "h": 20}, {"x": 7, "y": 400, "w": 1, "h": 30}]
        out, w, h = stack_layout(220, 999, kids, start_size=30)
        self.assertEqual([(c["x"], c["y"], c["w"], c["h"]) for c in out], [(0, 30, 220, 20), (0, 50, 220, 30)])
        self.assertEqual((w, h), (220, 80))

    def test_stroke_width_ignored_because_border_collapse(self):
        # mxStackLayout.borderCollapse is true (mxStackLayout.js:155): stroke widths add no gap.
        kids = [{"x": 0, "y": 0, "w": 1, "h": 20}, {"x": 0, "y": 0, "w": 1, "h": 30, "stroke_width": 2}]
        out, w, h = stack_layout(220, 999, kids, start_size=30)
        self.assertEqual(out[1]["y"], 50)
        self.assertEqual(h, 80)
        # with borderCollapse off, floor(sw/2) is added to the gap; parent height uses
        # last.y + last.height (not lastValue)
        out, w, h = stack_layout(220, 999, kids, start_size=30, border_collapse=False)
        self.assertEqual(out[1]["y"], 51)
        self.assertEqual(h, 81)

    def test_horizontal_and_flags(self):
        kids = [{"x": 0, "y": 0, "w": 50, "h": 1}, {"x": 0, "y": 0, "w": 70, "h": 1}]
        out, w, h = stack_layout(10, 100, kids, start_size=20, horizontal=True, spacing=5)
        self.assertEqual([(c["x"], c["y"], c["w"], c["h"]) for c in out], [(0, 20, 50, 80), (55, 20, 70, 80)])
        self.assertEqual((w, h), (125, 100))
        # resizeParentMax keeps the larger parent
        _, w, h = stack_layout(500, 100, kids, horizontal=True, resize_parent_max=True)
        self.assertEqual(w, 500)
        # resizeParent off + resizeLast: last child stretches to the parent
        out, w, h = stack_layout(300, 100, kids, horizontal=True, resize_parent=False, resize_last=True)
        self.assertEqual(out[1]["w"], 300 - out[1]["x"])
        self.assertEqual(w, 300)
        # fill off keeps child cross size
        out, _, _ = stack_layout(300, 100, kids, horizontal=True, fill=False)
        self.assertEqual(out[0]["h"], 1)

    def test_margins_and_border(self):
        kids = [{"x": 0, "y": 0, "w": 1, "h": 10}]
        out, w, h = stack_layout(100, 100, kids, border=2, margin_left=3, margin_right=4, margin_top=5, margin_bottom=6)
        self.assertEqual((out[0]["x"], out[0]["y"], out[0]["w"]), (5, 7, 100 - 3 - 4 - 4))
        self.assertEqual(h, 7 + 10 + 6 + 2)

    def test_emitted_table_geometry_is_a_fixed_point(self):
        def rows_doc(n, heights=None):
            rows = []
            for i in range(n):
                row = {"id": "r%d" % i, "label": "col%d" % i}
                if heights and i in heights:
                    row["h"] = heights[i]
                rows.append(row)
            return {"schema_version": 1, "kind": "raw", "pages": [{"id": "p", "cells": [
                {"id": "T", "type": "table", "x": 10, "y": 10, "w": 220, "title": "t", "rows": rows}]}]}

        for n, heights in ((1, None), (3, None), (5, {1: 40, 3: 18.5}), (20, None)):
            with self.subTest(rows=n):
                table = validate_raw(rows_doc(n, heights)).doc["pages"][0]["cells"][0]
                declared = geometry.table_row_geometry(table, S.TABLE_START_SIZE)
                kids = [{"x": x, "y": y, "w": w, "h": h} for (x, y, w, h) in declared]
                out, pw, ph = stack_layout(table["w"], table["h"], kids, start_size=S.TABLE_START_SIZE,
                                           resize_parent=True, resize_parent_max=False, resize_last=False)
                self.assertEqual([(c["x"], c["y"], c["w"], c["h"]) for c in out], declared)
                self.assertEqual((pw, ph), (table["w"], table["h"]))
                # and it is also reached from scrambled child geometry (draw.io re-layouts on edit)
                scrambled = [{"x": 7, "y": 500 - i, "w": 3, "h": h} for i, (_, _, _, h) in enumerate(declared)]
                out2, pw2, ph2 = stack_layout(table["w"], 9999, scrambled, start_size=S.TABLE_START_SIZE)
                self.assertEqual([(c["x"], c["y"], c["w"], c["h"]) for c in out2], declared)
                self.assertEqual(ph2, table["h"])


if __name__ == "__main__":
    unittest.main()
