import copy
import unittest

from diagram_tool.core import schema as S
from diagram_tool.core.errors import ValidationError
from diagram_tool.kinds.raw import validate_raw


def base_doc():
    return {
        "schema_version": 1, "kind": "raw", "title": "T", "theme": "mono",
        "pages": [{
            "id": "p1", "name": "Trang 1",
            "cells": [
                {"id": "A", "type": "vertex", "role": "box", "x": 40, "y": 40, "w": 160, "h": 60, "label": "A"},
                {"id": "G", "type": "vertex", "role": "container", "x": 40, "y": 160, "w": 400, "h": 240},
                {"id": "B", "type": "vertex", "parent": "G", "x": 20, "y": 40, "w": 120, "h": 50, "label": "B"},
                {"id": "T", "type": "table", "x": 500, "y": 40, "w": 220, "title": "ban",
                 "rows": [{"id": "id", "label": "id uuid PK", "role": "pk"}, "ten", {"label": "ten"}]},
                {"id": "E1", "type": "edge", "source": "A", "target": "B",
                 "exit": {"x": 1, "y": 0.5}, "entry": {"x": 0.5, "y": 0},
                 "points": [{"x": 240, "y": 70}, {"x": 240, "y": 180}, {"x": 120, "y": 180}]},
            ],
        }],
    }


def cells(doc):
    return doc["pages"][0]["cells"]


def nested_doc():
    return {
        "schema_version": 1, "kind": "raw",
        "pages": [{"id": "p", "cells": [
            {"id": "G", "type": "vertex", "role": "container", "x": 50, "y": 50, "w": 800, "h": 600},
            {"id": "H", "type": "vertex", "role": "container", "parent": "G", "x": 100, "y": 100, "w": 500, "h": 300},
            {"id": "X", "type": "vertex", "parent": "H", "x": 20, "y": 20, "w": 100, "h": 40},
            {"id": "Y", "type": "vertex", "parent": "G", "x": 600, "y": 20, "w": 100, "h": 40},
            {"id": "E", "type": "edge", "source": "X", "target": "Y",
             "exit": {"x": 0.5, "y": 1}, "entry": {"x": 0.5, "y": 1},
             "points": [{"x": 170, "y": 250}, {"x": 650, "y": 250}]},
        ]}],
    }


class ValidTest(unittest.TestCase):
    def test_base_valid_and_normalised(self):
        res = validate_raw(base_doc())
        doc = res.doc
        self.assertEqual(doc["theme"], "mono")
        page = doc["pages"][0]
        by = {c["id"]: c for c in page["cells"]}
        self.assertEqual(by["B"]["parent"], "G")
        self.assertEqual(by["E1"]["parent"], None)
        self.assertEqual(by["E1"]["end"], S.DEFAULT_END)
        self.assertEqual(by["E1"]["start"], "none")
        self.assertEqual(by["T"]["h"], S.TABLE_START_SIZE + 3 * S.TABLE_ROW_H)
        self.assertEqual([r["id"] for r in by["T"]["rows"]], ["id", "ten", "ten_2"])
        self.assertEqual(by["T"]["rows"][1]["role"], "plain")
        self.assertEqual(res.warnings, ())

    def test_page_size_derived(self):
        page = validate_raw(base_doc()).doc["pages"][0]
        self.assertEqual((page["width"], page["height"]), (760, 440))  # table right 720+40, G bottom 400+40
        d = base_doc()
        d["pages"][0]["width"] = 1600
        d["pages"][0]["height"] = 1000
        page = validate_raw(d).doc["pages"][0]
        self.assertEqual((page["width"], page["height"]), (1600, 1000))
        d = {"schema_version": 1, "kind": "raw", "pages": [{"id": "p", "cells": []}]}
        page = validate_raw(d).doc["pages"][0]
        self.assertEqual((page["width"], page["height"]), (850, 1100))

    def test_defaults_for_title_and_page_name(self):
        d = {"schema_version": 1, "kind": "raw", "pages": [{"id": "p", "cells": []}, {"id": "q", "cells": []}]}
        doc = validate_raw(d).doc
        self.assertEqual(doc["pages"][1]["name"], "Trang 2")
        self.assertEqual(doc["title"], "Trang 1")

    def test_nested_containers_with_offset_origins(self):
        doc = validate_raw(nested_doc()).doc
        edge = [c for c in doc["pages"][0]["cells"] if c["id"] == "E"][0]
        self.assertEqual(edge["parent"], "G")

    def test_edge_parent_inside_container(self):
        d = {"schema_version": 1, "kind": "raw", "pages": [{"id": "p", "cells": [
            {"id": "G", "type": "vertex", "role": "container", "x": 100, "y": 100, "w": 600, "h": 400},
            {"id": "X", "type": "vertex", "parent": "G", "x": 20, "y": 20, "w": 100, "h": 40},
            {"id": "Y", "type": "vertex", "parent": "G", "x": 300, "y": 20, "w": 100, "h": 40},
            {"id": "E", "type": "edge", "source": "X", "target": "Y",
             "exit": {"x": 0.5, "y": 1}, "entry": {"x": 0.5, "y": 1},
             "points": [{"x": 70, "y": 100}, {"x": 350, "y": 100}]},
        ]}]}
        self.assertEqual(validate_raw(d).doc["pages"][0]["cells"][3]["parent"], "G")
        d["pages"][0]["cells"][3]["points"] = [{"x": 170, "y": 200}, {"x": 450, "y": 200}]  # absolute coords: wrong
        with self.assertRaises(ValidationError):
            validate_raw(d)

    def test_straight_edge_without_ports(self):
        d = base_doc()
        c = cells(d)[-1]
        del c["points"], c["exit"], c["entry"]
        validate_raw(d)

    def test_self_loop(self):
        d = base_doc()
        d["pages"][0]["cells"].append({
            "id": "L", "type": "edge", "source": "A", "target": "A",
            "exit": {"x": 1, "y": 0.25}, "entry": {"x": 1, "y": 0.75},
            "points": [{"x": 240, "y": 55}, {"x": 240, "y": 85}]})
        res = validate_raw(d)
        loop = res.doc["pages"][0]["cells"][-1]
        self.assertTrue(loop["loop"])
        self.assertEqual(loop["parent"], None)

    def test_labels(self):
        d = base_doc()
        e = cells(d)[-1]
        e["labels"] = [{"text": "n", "pos": 0.5, "dy": -8}, {"id": "end", "text": "1..*", "pos": 1}]
        out = validate_raw(d).doc["pages"][0]["cells"][-1]["labels"]
        self.assertEqual(out[0], {"id": None, "text": "n", "pos": 0.5, "dx": 0, "dy": -8})
        self.assertEqual(out[1]["id"], "end")
        e2 = base_doc()
        cells(e2)[-1]["label"] = "nhãn"
        out = validate_raw(e2).doc["pages"][0]["cells"][-1]["labels"]
        self.assertEqual(out, [{"id": None, "text": "nhãn", "pos": 0, "dx": 0, "dy": 0}])

    def test_attrs_meta_and_style_raw(self):
        d = base_doc()
        d["meta"] = {"owner": "x"}
        cells(d)[0]["attrs"] = {"meta_ref": "A.b"}
        cells(d)[0]["style_raw"] = "rounded=1; strokeWidth=2"
        res = validate_raw(d)
        self.assertEqual(res.doc["meta"], {"owner": "x"})
        self.assertEqual(res.doc["pages"][0]["cells"][0]["style_raw"], "rounded=1;strokeWidth=2")
        self.assertEqual(len(res.warnings), 1)
        self.assertIn("pages[0].cells[0].style_raw", res.warnings[0])

    def test_input_not_mutated_and_deterministic(self):
        d = base_doc()
        snapshot = copy.deepcopy(d)
        a = validate_raw(d).doc
        self.assertEqual(d, snapshot)
        shuffled = base_doc()
        shuffled["pages"][0]["cells"] = [dict(reversed(list(c.items()))) for c in cells(shuffled)]
        self.assertEqual(validate_raw(shuffled).doc, a)


class InvalidTest(unittest.TestCase):
    def assert_error(self, doc, path_part, msg_part=""):
        with self.assertRaises(ValidationError) as ctx:
            validate_raw(doc)
        text = str(ctx.exception)
        text.encode("ascii")
        self.assertIn(path_part, text)
        self.assertIn(msg_part, text)

    def mutate(self, fn):
        d = base_doc()
        fn(d)
        return d

    def test_document_level(self):
        self.assert_error([], "expected an object")
        self.assert_error({"kind": "raw", "pages": []}, "schema_version", "missing")
        self.assert_error({"schema_version": 2, "kind": "raw", "pages": [{"id": "p", "cells": []}]}, "schema_version")
        self.assert_error({"schema_version": True, "kind": "raw", "pages": [{"id": "p", "cells": []}]}, "schema_version")
        self.assert_error({"schema_version": 1, "kind": "erd", "pages": [{"id": "p", "cells": []}]}, "kind")
        self.assert_error({"schema_version": 1, "kind": "raw", "pages": []}, "pages", "empty")
        self.assert_error({"schema_version": 1, "kind": "raw", "pages": [{"id": "p", "cells": []}], "x": 1}, "x", "unknown key")
        self.assert_error({"schema_version": 1, "kind": "raw", "theme": "neon", "pages": [{"id": "p", "cells": []}]}, "theme")
        self.assert_error({"schema_version": 1, "kind": "raw",
                           "pages": [{"id": "p", "cells": []}, {"id": "p", "cells": []}]}, "pages[1].id", "duplicate")

    def test_meta_generator_rejected(self):
        self.assert_error(self.mutate(lambda d: d.update(meta={"generator": "x"})), "meta.generator")
        self.assert_error(self.mutate(lambda d: d.update(meta={"title": "x"})), "meta.title")
        self.assert_error(self.mutate(lambda d: d.update(meta={"label": "x"})), "meta.label", "reserved")
        self.assert_error(self.mutate(lambda d: d.update(meta={"1bad": "x"})), "meta.1bad")
        self.assert_error(self.mutate(lambda d: d.update(meta={"k": 5})), "meta.k", "string")

    def test_attrs_rules(self):
        for key in ("id", "label", "placeholders", "placeholder", "tooltip", "link"):
            d = self.mutate(lambda d, key=key: cells(d)[0].update(attrs={key: "1"}))
            self.assert_error(d, "pages[0].cells[0].attrs." + key, "reserved")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(attrs={"a:b": "1"})), "attrs.a:b")

    def test_cell_basics(self):
        self.assert_error(self.mutate(lambda d: cells(d)[0].pop("type")), "cells[0]", "type")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(type="blob")), "cells[0].type")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(id="B")), "cells[2].id", "duplicate")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(id="a:b")), "cells[0].id", "invalid id")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(zzz=1)), "cells[0].zzz", "unknown key")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(role="table")), "cells[0].role")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(variant="Bad Name")), "cells[0].variant")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(tags=["ok", "no good"])), "cells[0].tags[1]")
        self.assert_error(self.mutate(lambda d: cells(d).__setitem__(0, 5)), "cells[0]", "object")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(label="a\x01b")), "cells[0].label", "control")

    def test_numbers(self):
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(x=True)), "cells[0].x", "number")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(x="40")), "cells[0].x", "number")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(x=float("nan"))), "cells[0].x", "finite")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(x=float("inf"))), "cells[0].x", "finite")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(w=0)), "cells[0].w", "> 0")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(h=-5)), "cells[0].h", "> 0")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(x=10 ** 9)), "cells[0].x", "range")
        self.assert_error(self.mutate(lambda d: d["pages"][0].update(width=0)), "pages[0].width")
        self.assert_error(self.mutate(lambda d: d["pages"][0].update(width=False)), "pages[0].width")

    def test_parent_rules(self):
        self.assert_error(self.mutate(lambda d: cells(d)[2].update(parent="nope")), "cells[2].parent", "unknown")
        self.assert_error(self.mutate(lambda d: cells(d)[2].update(parent="A")), "cells[2].parent", "container")
        self.assert_error(self.mutate(lambda d: cells(d)[2].update(parent="T")), "cells[2].parent", "container")
        self.assert_error(self.mutate(lambda d: cells(d)[1].update(parent="G")), "cells[1].parent", "cycle")

        def cycle(d):
            cells(d)[1]["parent"] = "H"
            cells(d).append({"id": "H", "type": "vertex", "role": "container", "parent": "G",
                             "x": 0, "y": 0, "w": 10, "h": 10})
        self.assert_error(self.mutate(cycle), "parent", "cycle")

    def test_containment(self):
        self.assert_error(self.mutate(lambda d: cells(d)[2].update(x=300)), "cells[2]", "outside its parent")
        self.assert_error(self.mutate(lambda d: cells(d)[2].update(y=-1)), "cells[2]", "outside its parent")
        self.assert_error(self.mutate(lambda d: cells(d)[2].update(h=400)), "cells[2]", "outside its parent")

    def test_table_rules(self):
        self.assert_error(self.mutate(lambda d: cells(d)[3].update(h=100)), "cells[3].h", "computed")
        self.assert_error(self.mutate(lambda d: cells(d)[3].update(rows=[])), "cells[3].rows", "empty")
        self.assert_error(self.mutate(lambda d: cells(d)[3].update(rows=["a", {"id": "a", "label": "x"}, {"id": "a", "label": "y"}])),
                          "cells[3].rows[2].id", "duplicate")
        self.assert_error(self.mutate(lambda d: cells(d)[3].update(rows=[{"label": "x", "role": "zz"}])), "rows[0].role")
        self.assert_error(self.mutate(lambda d: cells(d)[3].update(rows=[{"role": "pk"}])), "rows[0]", "label")
        self.assert_error(self.mutate(lambda d: cells(d)[3].update(rows=[""])), "rows[0]", "empty")
        self.assert_error(self.mutate(lambda d: cells(d)[3].update(rows=[{"label": "x", "h": 0}])), "rows[0].h")
        self.assert_error(self.mutate(lambda d: cells(d)[3].pop("title")), "cells[3]", "title")
        self.assert_error(self.mutate(lambda d: cells(d)[3].update(rows=[5])), "rows[0]", "object")

    def test_row_ids_stable_and_explicit_win(self):
        d = self.mutate(lambda d: cells(d)[3].update(rows=["ten", {"id": "ten", "label": "other"}, "ten"]))
        rows = validate_raw(d).doc["pages"][0]["cells"][3]["rows"]
        self.assertEqual([r["id"] for r in rows], ["ten_2", "ten", "ten_3"])
        d = self.mutate(lambda d: cells(d)[3].update(rows=[{"label": "-", "role": "separator"}, {"role": "separator"}]))
        rows = validate_raw(d).doc["pages"][0]["cells"][3]["rows"]
        self.assertEqual([r["id"] for r in rows], ["row", "row_2"])

    def test_edge_references(self):
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(source="zzz")), "cells[4].source", "unknown")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(target="E1")), "cells[4].target", "another edge")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(target="T:id")), "cells[4].target", "invalid id")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(parent="G")), "cells[4].parent", "ancestor of both")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(parent="A")), "cells[4].parent", "ancestor of both")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(parent="zzz")), "cells[4].parent", "unknown")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(start="triangle")), "cells[4].start")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(end=3)), "cells[4].end")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(line="wavy")), "cells[4].line")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(stroke_width=0)), "cells[4].stroke_width")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(role="inherit")), "cells[4].role")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(weight=1)), "cells[4].weight", "unknown")

    def test_all_arrow_symbols_accepted(self):
        for sym in S.ARROW_SYMBOLS:
            d = self.mutate(lambda d, sym=sym: cells(d)[-1].update(start=sym, end=sym))
            validate_raw(d)

    def test_declared_parent_must_cover_both_ends(self):
        d = nested_doc()
        cells(d)[-1]["parent"] = "H"
        self.assert_error(d, "cells[4].parent", "ancestor of both")
        cells(d)[-1]["parent"] = "G"
        validate_raw(d)

    def test_ports(self):
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(exit={"x": 1, "y": 1})), "exit", "corner")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(exit={"x": 0, "y": 0})), "exit", "corner")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(exit={"x": 0.5, "y": 0.5})), "exit", "boundary")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(exit={"x": 2, "y": 0.5})), "exit.x")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(exit={"x": 1})), "exit", "missing")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].pop("exit")), "cells[4].exit", "required")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].pop("entry")), "cells[4].entry", "required")

    def test_route_rules(self):
        def pts(d, value):
            cells(d)[-1]["points"] = value

        # first point not aligned with the exit port (exit right -> y must be 70)
        self.assert_error(self.mutate(lambda d: pts(d, [{"x": 240, "y": 71}, {"x": 240, "y": 180}, {"x": 120, "y": 180}])),
                          "points[0]", "not aligned")
        # last point not aligned with the entry port (entry top -> x must be 120)
        self.assert_error(self.mutate(lambda d: pts(d, [{"x": 240, "y": 70}, {"x": 240, "y": 180}, {"x": 121, "y": 180}])),
                          "points[2]", "not aligned")
        # diagonal between points
        self.assert_error(self.mutate(lambda d: pts(d, [{"x": 240, "y": 70}, {"x": 250, "y": 180}, {"x": 120, "y": 180}])),
                          "points[1]", "diagonal")
        # segment shorter than 2
        self.assert_error(self.mutate(lambda d: pts(d, [{"x": 240, "y": 70}, {"x": 240, "y": 71}, {"x": 120, "y": 71}])),
                          "points[1]", "shorter")
        # coincident consecutive points
        self.assert_error(self.mutate(lambda d: pts(d, [{"x": 240, "y": 70}, {"x": 240, "y": 70}, {"x": 120, "y": 70}])),
                          "points[1]", "shorter")
        # first point on the port itself / too close
        self.assert_error(self.mutate(lambda d: pts(d, [{"x": 200, "y": 70}, {"x": 200, "y": 180}, {"x": 120, "y": 180}])),
                          "points[0]", "closer")
        self.assert_error(self.mutate(lambda d: pts(d, [{"x": 201, "y": 70}, {"x": 201, "y": 180}, {"x": 120, "y": 180}])),
                          "points[0]", "closer")
        # last point too close to the entry port (entry abs (120,200))
        self.assert_error(self.mutate(lambda d: pts(d, [{"x": 240, "y": 70}, {"x": 240, "y": 199}, {"x": 120, "y": 199}])),
                          "points[2]", "closer")
        # bad point objects
        self.assert_error(self.mutate(lambda d: pts(d, [{"x": 240}])), "points[0]", "missing")
        self.assert_error(self.mutate(lambda d: pts(d, [{"x": True, "y": 1}])), "points[0].x")
        self.assert_error(self.mutate(lambda d: pts(d, "no")), "points", "array")

    def test_route_bottom_exit_left_entry(self):
        d = {"schema_version": 1, "kind": "raw", "pages": [{"id": "p", "cells": [
            {"id": "A", "type": "vertex", "x": 0, "y": 0, "w": 100, "h": 40},
            {"id": "B", "type": "vertex", "x": 300, "y": 200, "w": 100, "h": 40},
            {"id": "E", "type": "edge", "source": "A", "target": "B",
             "exit": {"x": 0.5, "y": 1}, "entry": {"x": 0, "y": 0.5},
             "points": [{"x": 50, "y": 220}]},
        ]}]}
        validate_raw(d)  # corner (50,220): x of exit (bottom), y of entry (left)
        d["pages"][0]["cells"][2]["points"] = [{"x": 51, "y": 220}]
        with self.assertRaises(ValidationError):
            validate_raw(d)

    def test_self_loop_needs_two_points(self):
        d = base_doc()
        d["pages"][0]["cells"].append({"id": "L", "type": "edge", "source": "A", "target": "A"})
        self.assert_error(d, "cells[5]", "at least 2 points")
        d["pages"][0]["cells"][-1].update(
            exit={"x": 1, "y": 0.25}, entry={"x": 1, "y": 0.75}, points=[{"x": 240, "y": 55}])
        self.assert_error(d, "cells[5]", "at least 2 points")

    def test_labels_rules(self):
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(label="a", labels=[{"text": "b"}])), "cells[4]", "not both")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(labels=[{"pos": 0}])), "labels[0]", "text")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(labels=[{"text": "a"}, {"text": "b"}])), "labels[1]", "id")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(labels=[{"text": "a", "id": "x"}, {"text": "b", "id": "x"}])),
                          "labels[1].id", "duplicate")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(labels=[{"text": "a", "pos": 2}])), "labels[0].pos")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(labels=[{"text": "a", "weird": 1}])), "labels[0].weird")

    def test_style_raw_rules(self):
        for style in ("html=1", "html=0", "fooBar=1", "exitDX=0", "rounded=1;rounded=0", "text2", "strokeWidth=",
                      "startSize=40", "childLayout=stackLayout", "shape=ellipse", "ellipse", "swimlane",
                      "portConstraint=eastwest", "points=[[0,0]]"):
            d = self.mutate(lambda d, style=style: cells(d)[3].update(style_raw=style))
            self.assert_error(d, "cells[3].style_raw")
        for style in ("exitX=0.5", "entryY=1", "edgeStyle=none", "noEdgeStyle=1", "curved=1", "elbow=vertical",
                      "perimeterSpacing=5", "orthogonalLoop=1", "swimlaneFillColor=#fff"):
            d = self.mutate(lambda d, style=style: cells(d)[-1].update(style_raw=style))
            self.assert_error(d, "cells[4].style_raw")
        for style in ("html=1", "html=0", "fooBar=1", "exitDX=0", "rounded=1;rounded=0", "text2", "strokeWidth="):
            d = self.mutate(lambda d, style=style: cells(d)[0].update(style_raw=style))
            self.assert_error(d, "cells[0].style_raw")
        # startSize is a swimlane header size on vertices but a marker size on edges: both allowed in
        # their own lists only, and exit* only on edges.
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(style_raw="exitX=0")), "style_raw", "exitX")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(style_raw="swimlaneFillColor=#fff")), "style_raw")
        validate_raw(self.mutate(lambda d: cells(d)[0].update(style_raw="fontStyle=1;strokeWidth=2")))
        validate_raw(self.mutate(lambda d: cells(d)[-1].update(style_raw="startSize=12;endSize=12")))

    def test_trailing_newline_not_accepted(self):
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(id="A\n")), "cells[0].id", "invalid id")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(variant="new\n")), "cells[0].variant")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(tags=["x\n"])), "cells[0].tags[0]")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(attrs={"owner\n": "1"})), "attrs")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(attrs={"xmlns": "1"})), "attrs.xmlns", "xml")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(attrs={"XMLfoo": "1"})), "attrs.XMLfoo", "xml")

    def test_derived_row_id_is_bounded(self):
        d = self.mutate(lambda d: cells(d)[3].update(rows=["a" * 3000]))
        rid = validate_raw(d).doc["pages"][0]["cells"][3]["rows"][0]["id"]
        self.assertLessEqual(len(rid), 200)
        d = self.mutate(lambda d: cells(d)[3].update(rows=["a" * 3000, "a" * 3000]))
        rows = validate_raw(d).doc["pages"][0]["cells"][3]["rows"]
        self.assertNotEqual(rows[0]["id"], rows[1]["id"])
        self.assertLessEqual(len(rows[1]["id"]), 200)

    def test_output_precision_guard(self):
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(x=10.25)), "cells[0].x", "decimal")
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(w=0.04)), "cells[0].w", "decimal")
        self.assert_error(self.mutate(lambda d: cells(d)[3].update(w=100.55)), "cells[3].w", "decimal")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(exit={"x": 1, "y": 0.123456})), "exit.y", "decimal")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(labels=[{"text": "a", "pos": 0.25}])), "pos", "decimal")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(labels=[{"text": "a", "dy": -8.33}])), "dy", "decimal")
        self.assert_error(self.mutate(lambda d: cells(d)[-1].update(points=[{"x": 240.05, "y": 70}])), "points[0].x", "decimal")
        validate_raw(self.mutate(lambda d: cells(d)[0].update(x=10.5, w=160.1)))
        d = self.mutate(lambda d: cells(d)[-1].update(exit={"x": 1, "y": 0.1234}))
        with self.assertRaises(ValidationError):  # port moved off y=70: points[0] no longer aligned
            validate_raw(d)

    def test_negative_top_level_rejected(self):
        self.assert_error(self.mutate(lambda d: cells(d)[0].update(x=-10)), "cells[0]", ">= 0")

    def test_edge_from_container_to_its_child(self):
        d = {"schema_version": 1, "kind": "raw", "pages": [{"id": "p", "cells": [
            {"id": "G", "type": "vertex", "role": "container", "x": 100, "y": 100, "w": 600, "h": 400},
            {"id": "X", "type": "vertex", "parent": "G", "x": 20, "y": 20, "w": 100, "h": 40},
            {"id": "E", "type": "edge", "source": "G", "target": "X"},
        ]}]}
        self.assertEqual(validate_raw(d).doc["pages"][0]["cells"][2]["parent"], "G")
        d["pages"][0]["cells"][2]["parent"] = "G"
        validate_raw(d)

    def test_self_loop_parents(self):
        loop = {"type": "edge", "exit": {"x": 1, "y": 0.25}, "entry": {"x": 1, "y": 0.75}}
        d = {"schema_version": 1, "kind": "raw", "pages": [{"id": "p", "cells": [
            {"id": "G", "type": "vertex", "role": "container", "x": 100, "y": 100, "w": 600, "h": 400},
            {"id": "X", "type": "vertex", "parent": "G", "x": 20, "y": 100, "w": 100, "h": 40},
            dict(loop, id="L1", source="X", target="X",
                 points=[{"x": 160, "y": 110}, {"x": 160, "y": 130}]),
            dict(loop, id="L2", source="G", target="G",
                 points=[{"x": 740, "y": 200}, {"x": 740, "y": 400}]),
        ]}]}
        cs = validate_raw(d).doc["pages"][0]["cells"]
        self.assertEqual(cs[2]["parent"], "G")      # vertex loop lives in its container
        self.assertIsNone(cs[3]["parent"])          # container loop lives in the container's parent
        d["pages"][0]["cells"][3]["parent"] = "G"
        self.assert_error(d, "cells[3].parent", "ancestor of both")

    def test_declared_parent_higher_than_lca(self):
        # X, Y both inside H (LCA = H), H inside G (origin 50,50), H at (100,100) in G.
        d = {"schema_version": 1, "kind": "raw", "pages": [{"id": "p", "cells": [
            {"id": "G", "type": "vertex", "role": "container", "x": 50, "y": 50, "w": 800, "h": 600},
            {"id": "H", "type": "vertex", "role": "container", "parent": "G", "x": 100, "y": 100, "w": 500, "h": 300},
            {"id": "X", "type": "vertex", "parent": "H", "x": 20, "y": 20, "w": 100, "h": 40},
            {"id": "Y", "type": "vertex", "parent": "H", "x": 300, "y": 20, "w": 100, "h": 40},
            {"id": "E", "type": "edge", "source": "X", "target": "Y",
             "exit": {"x": 0.5, "y": 1}, "entry": {"x": 0.5, "y": 1},
             "points": [{"x": 70, "y": 150}, {"x": 350, "y": 150}]},   # H coordinates
        ]}]}
        self.assertEqual(validate_raw(d).doc["pages"][0]["cells"][4]["parent"], "H")
        # declaring the higher ancestor G changes the coordinate system to G's
        d["pages"][0]["cells"][4]["parent"] = "G"
        self.assert_error(d, "cells[4].points[0]", "not aligned")           # H-relative points rejected
        d["pages"][0]["cells"][4]["points"] = [{"x": 170, "y": 250}, {"x": 450, "y": 250}]  # G coordinates
        self.assertEqual(validate_raw(d).doc["pages"][0]["cells"][4]["parent"], "G")
        # a declared parent that is not an ancestor of both ends fails
        cells(d).append({"id": "R", "type": "vertex", "role": "container", "x": 0, "y": 700, "w": 10, "h": 10})
        cells(d)[4]["parent"] = "R"
        self.assert_error(d, "cells[4].parent", "ancestor of both")

    def test_page_size_from_edge_points_and_deep_children(self):
        d = nested_doc()
        cells(d)[4]["points"] = [{"x": 170, "y": 900}, {"x": 650, "y": 900}]
        page = validate_raw(d).doc["pages"][0]
        self.assertEqual(page["height"], 990)    # G origin 50 + 900 + 40 margin
        self.assertEqual(page["width"], 890)     # G right edge 850 + 40

    def test_route_faces_left_and_top(self):
        base = lambda ex, en, pts: {"schema_version": 1, "kind": "raw", "pages": [{"id": "p", "cells": [
            {"id": "A", "type": "vertex", "x": 300, "y": 300, "w": 100, "h": 40},
            {"id": "B", "type": "vertex", "x": 0, "y": 0, "w": 100, "h": 40},
            {"id": "E", "type": "edge", "source": "A", "target": "B", "exit": ex, "entry": en, "points": pts},
        ]}]}
        # exit left (y of port = 320), entry top... B top is y=0, entry bottom (50, 40)
        good = base({"x": 0, "y": 0.5}, {"x": 0.5, "y": 1}, [{"x": 250, "y": 320}, {"x": 250, "y": 100}, {"x": 50, "y": 100}])
        validate_raw(good)
        bad = base({"x": 0, "y": 0.5}, {"x": 0.5, "y": 1}, [{"x": 250, "y": 321}, {"x": 250, "y": 100}, {"x": 50, "y": 100}])
        self.assert_error(bad, "points[0]", "y = 320")
        # exit top (x of port = 350) and entry on the right face of B (y of port = 20)
        good = base({"x": 0.5, "y": 0}, {"x": 1, "y": 0.5}, [{"x": 350, "y": 20}])
        validate_raw(good)
        bad = base({"x": 0.5, "y": 0}, {"x": 1, "y": 0.5}, [{"x": 351, "y": 20}])
        self.assert_error(bad, "points[0]", "x = 350")

    def test_ascii_messages_for_vietnamese(self):
        d = self.mutate(lambda d: cells(d)[0].update(id="khối x"))
        with self.assertRaises(ValidationError) as ctx:
            validate_raw(d)
        str(ctx.exception).encode("ascii")


if __name__ == "__main__":
    unittest.main()
