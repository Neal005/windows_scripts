import copy
import unittest
import xml.etree.ElementTree as ET

from diagram_tool import GENERATOR
from diagram_tool.core import schema as S
from diagram_tool.core.errors import ValidationError
from diagram_tool.emit import styles as ST
from diagram_tool.emit import themes as T
from diagram_tool.kinds.raw import to_drawio, validate_raw
from diagram_tool.sim.segment_connector import segment_connector
from diagram_tool.sim.stack_layout import stack_layout

from tests.fixtures import full_doc


# ---- helpers -----------------------------------------------------------------------------

def parse_style(text):
    """-> (bare tokens list, ordered list of (key, value))."""
    assert text.endswith(";"), text
    tokens, pairs = [], []
    for seg in text[:-1].split(";"):
        if "=" in seg:
            k, v = seg.split("=", 1)
            pairs.append((k, v))
        else:
            tokens.append(seg)
    return tokens, pairs


def style_dict(text):
    return dict(parse_style(text)[1])


def num(text):
    return float(text) if text is not None else 0.0


class Cell:
    pass


def read_pages(xml):
    root = ET.fromstring(xml)
    assert root.tag == "mxfile"
    pages = []
    for diagram in root.findall("diagram"):
        model = diagram.find("mxGraphModel")
        cells = []
        zero = None
        for el in model.find("root"):
            c = Cell()
            if el.tag == "object":
                c.wrapper = el
                inner = el.find("mxCell")
                c.id = el.get("id")
                c.value = el.get("label")
                c.attrs = {k: v for k, v in el.attrib.items() if k not in ("id", "label")}
            else:
                inner = el
                c.wrapper = None
                c.id = el.get("id")
                c.value = el.get("value")
                c.attrs = {}
            c.cell = inner
            c.style = inner.get("style")
            c.parent = inner.get("parent")
            c.source = inner.get("source")
            c.target = inner.get("target")
            c.vertex = inner.get("vertex") == "1"
            c.edge = inner.get("edge") == "1"
            geo = inner.find("mxGeometry")
            c.geo = geo
            c.points = []
            c.offset = None
            if geo is not None:
                arr = geo.find("Array")
                if arr is not None:
                    c.points = [(num(p.get("x")), num(p.get("y"))) for p in arr.findall("mxPoint")]
                off = [p for p in geo.findall("mxPoint") if p.get("as") == "offset"]
                if off:
                    c.offset = (num(off[0].get("x")), num(off[0].get("y")))
            if c.id == "0":
                zero = c
            cells.append(c)
        pages.append({"diagram": diagram, "model": model, "cells": cells, "zero": zero})
    return pages


def by_id(cells):
    return {c.id: c for c in cells}


def hex_to_rgb(color):
    return tuple(int(color[i:i + 2], 16) for i in (1, 3, 5))


def luminance(color):
    def lin(v):
        v /= 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = hex_to_rgb(color)
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def lightness(color):
    y = luminance(color)
    return 116 * (y ** (1 / 3.0)) - 16 if y > 0.008856 else 903.3 * y


def render(doc=None, theme=None):
    return to_drawio(full_doc() if doc is None else doc, theme)[0]


COLOR_KEYS = ("fillColor", "strokeColor", "fontColor", "labelBackgroundColor", "swimlaneFillColor")


def all_colors(xml):
    out = []
    for page in read_pages(xml):
        out.append(page["model"].get("background"))
        for c in page["cells"]:
            if c.style:
                d = style_dict(c.style)
                out += [d[k] for k in COLOR_KEYS if k in d and d[k] != "none"]
    return out


# ---- structure ----------------------------------------------------------------------------

class StructureTest(unittest.TestCase):
    def setUp(self):
        self.xml = render()
        self.pages = read_pages(self.xml)

    def test_frame(self):
        root = ET.fromstring(self.xml)
        self.assertEqual(root.get("host"), "app.diagrams.net")
        self.assertEqual([d.get("id") for d in root.findall("diagram")], ["p1", "p2"])
        self.assertEqual([d.get("name") for d in root.findall("diagram")], ["Trang 1", "Trang 2"])
        for page in self.pages:
            m = page["model"]
            self.assertEqual(m.get("adaptiveColors"), "none")
            self.assertEqual(m.get("background"), "#FFFFFF")
            self.assertEqual((m.get("grid"), m.get("gridSize"), m.get("math"), m.get("shadow")), ("1", "10", "0", "0"))
            self.assertEqual(m.get("pageWidth") is not None and m.get("pageHeight") is not None, True)
        self.assertEqual(self.pages[1]["model"].get("pageWidth"), "600")

    def test_cell_zero_is_object_with_generator(self):
        for page in self.pages:
            z = page["zero"]
            self.assertIsNotNone(z.wrapper)
            self.assertEqual(z.wrapper.get("generator"), GENERATOR)
            self.assertEqual(z.wrapper.get("title"), "Tong hop")
            self.assertEqual(z.wrapper.get("owner"), "team")
            self.assertEqual(z.cell.tag, "mxCell")
            self.assertIsNone(z.cell.get("value"))
            self.assertEqual(page["cells"][1].id, "1")
            self.assertEqual(page["cells"][1].parent, "0")

    def test_ids_unique_and_references_resolve(self):
        for page in self.pages:
            ids = [c.id for c in page["cells"]]
            self.assertEqual(len(ids), len(set(ids)))
            known = set(ids)
            for c in page["cells"][2:]:
                self.assertIn(c.parent, known, c.id)
                if c.edge:
                    self.assertIn(c.source, known)
                    self.assertIn(c.target, known)
                    self.assertTrue(by_id(page["cells"])[c.source].vertex)
                    self.assertTrue(by_id(page["cells"])[c.target].vertex)

    def test_id_scheme(self):
        cells = by_id(self.pages[0]["cells"])
        for cid in ("p1:C", "p1:T5", "p1:T5:col0", "p1:E1c", "p1:E1c:end", "p1:A3"):
            self.assertIn(cid, cells)
        self.assertEqual(cells["p1:T5:col0"].parent, "p1:T5")
        self.assertEqual(cells["p1:E1c:end"].parent, "p1:E1c")
        self.assertEqual(cells["p1:B1"].parent, "p1:C2")
        self.assertEqual(cells["p1:C"].parent, "1")

    def test_table_rows_follow_table_and_labels_follow_edge(self):
        ids = [c.id for c in self.pages[0]["cells"]]
        i = ids.index("p1:T5")
        self.assertEqual(ids[i + 1:i + 7], ["p1:T5:col0", "p1:T5:col1", "p1:T5:col2", "p1:T5:col3", "p1:T5:sep", "p1:T5:nt"])
        j = ids.index("p1:E1c")
        self.assertEqual(ids[j + 1], "p1:E1c:end")

    def test_line_feed_no_bom_trailing_newline(self):
        self.assertNotIn("\r", self.xml)
        self.assertFalse(self.xml.startswith("﻿"))
        self.assertTrue(self.xml.endswith("</mxfile>\n"))
        self.assertFalse(self.xml.endswith("\n\n"))
        self.assertNotIn("\t", self.xml)

    def test_object_wrapper_for_attrs(self):
        cells = by_id(self.pages[0]["cells"])
        b1 = cells["p1:B1"]
        self.assertIsNotNone(b1.wrapper)
        self.assertEqual(b1.wrapper.get("label"), "Khối B1")
        self.assertEqual(b1.attrs, {"meta_ref": "x.y", "entity": "b1"})
        self.assertIsNone(b1.cell.get("value"))      # label moved to the <object>
        self.assertIsNone(cells["p1:B3"].wrapper)
        e = by_id(self.pages[1]["cells"])["p2:E"]
        self.assertEqual(e.attrs, {"meta_ref": "rel1"})
        self.assertEqual((e.source, e.target), ("p2:X", "p2:Y"))

    def test_label_escaping_roundtrip(self):
        b2 = by_id(self.pages[0]["cells"])["p1:B2"]
        self.assertEqual(b2.value, "a <=> b\nList<Entity> & \"q\" 'r'")
        self.assertIn("&#10;", self.xml)
        self.assertIn("a &lt;=&gt; b", self.xml)
        n = by_id(self.pages[0]["cells"])["p1:N"]
        self.assertEqual(n.value, "Ghi chú: Đường")
        self.assertIn("Ghi chú: Đường", self.xml)   # Vietnamese kept as UTF-8

    def test_input_order_of_json_keys_does_not_matter(self):
        doc = full_doc()
        shuffled = copy.deepcopy(doc)

        def rev(obj):
            if isinstance(obj, dict):
                return {k: rev(v) for k, v in reversed(list(obj.items()))}
            if isinstance(obj, list):
                return [rev(v) for v in obj]
            return obj
        self.assertEqual(render(rev(shuffled)), render(doc))

    def test_deterministic(self):
        self.assertEqual(render(), render())
        self.assertEqual(render(theme="accent"), render(theme="accent"))

    def test_warnings_and_theme_override(self):
        xml, warnings = to_drawio(full_doc())
        self.assertEqual(len(warnings), 2)
        self.assertTrue(all("style_raw" in w for w in warnings))
        with self.assertRaises(ValidationError):
            to_drawio(full_doc(), "neon")
        self.assertNotEqual(render(theme="accent"), render(theme="mono"))
        d = full_doc()
        d["theme"] = "accent"
        self.assertEqual(render(d), render(theme="accent"))


# ---- styles --------------------------------------------------------------------------------

class StyleTest(unittest.TestCase):
    def setUp(self):
        self.xml = render()
        self.pages = read_pages(self.xml)
        self.styled = [c for p in self.pages for c in p["cells"] if c.style]

    def test_keys_allowed_unique_and_html_zero(self):
        for c in self.styled:
            tokens, pairs = parse_style(c.style)
            keys = [k for k, _ in pairs]
            self.assertEqual(len(keys), len(set(keys)), (c.id, c.style))
            allowed = ST.EDGE_EMIT_KEYS if c.edge else ST.VERTEX_EMIT_KEYS
            for k in keys:
                self.assertIn(k, allowed, (c.id, k))
            for t in tokens:
                self.assertIn(t, ST.VERTEX_EMIT_BARE, (c.id, t))
            self.assertEqual(style_dict(c.style).get("html"), "0", c.id)
            if tokens:
                self.assertEqual(c.style.index(tokens[0] + ";"), 0)

    def test_explicit_properties_everywhere(self):
        for c in self.styled:
            d = style_dict(c.style)
            for k in ("fontColor", "fontFamily", "fontSize", "labelBackgroundColor", "strokeColor"):
                self.assertIn(k, d, (c.id, k))
            self.assertEqual(d["fontFamily"], "Arial")
            if c.edge:
                for k in ("endArrow", "startArrow", "endFill", "startFill", "rounded", "strokeWidth", "dashed", "edgeStyle"):
                    self.assertIn(k, d, (c.id, k))
                self.assertEqual(d["rounded"], "0")
                self.assertEqual(d["edgeStyle"], "orthogonalEdgeStyle")
            else:
                self.assertIn("fillColor", d, c.id)

    def test_arrow_markers_and_fill_per_end(self):
        cells = by_id(self.pages[0]["cells"])
        for i, sym in enumerate(S.ARROW_SYMBOLS):
            d = style_dict(cells["p1:A%d" % i].style)
            arrow, fill, size = ST.ARROWS[sym]
            self.assertEqual((d["endArrow"], d["endFill"]), (arrow, str(fill)), sym)
            self.assertEqual((d["startArrow"], d["startFill"]), (arrow, str(fill)), sym)
            self.assertEqual(d.get("endSize"), None if size is None else str(size), sym)
            self.assertEqual(d.get("startSize"), None if size is None else str(size), sym)
        # ends are independent
        d = style_dict(cells["p1:E2c"].style)
        self.assertEqual((d["startArrow"], d["endArrow"]), ("ERoneToMany", "ERzeroToMany"))
        d = style_dict(cells["p1:ETab"].style)
        self.assertEqual((d["startArrow"], d["startFill"], d["startSize"]), ("block", "0", "16"))
        self.assertEqual((d["endArrow"], d["endFill"], d["endSize"]), ("diamondThin", "0", "24"))

    def test_arrow_table_written_by_hand(self):
        expected = {
            "none": ("none", 0, None), "classic": ("classic", 1, None), "open": ("open", 0, None),
            "block": ("block", 1, None), "block-open": ("block", 0, None),
            "diamond": ("diamond", 1, None), "diamond-open": ("diamond", 0, None),
            "er-one": ("ERone", 0, None), "er-mandatory-one": ("ERmandOne", 0, None),
            "er-many": ("ERmany", 0, None), "er-zero-one": ("ERzeroToOne", 0, None),
            "er-zero-many": ("ERzeroToMany", 0, None), "er-one-many": ("ERoneToMany", 0, None),
            "inherit": ("block", 0, 16), "realize": ("block", 0, 16),
            "aggregation": ("diamondThin", 0, 24), "composition": ("diamondThin", 1, 24),
            "dependency": ("open", 0, None),
        }
        self.assertEqual(ST.ARROWS, expected)

    def test_attrs_and_meta_are_escaped(self):
        doc = full_doc()
        doc["meta"] = {"owner": 'a&b <c> "d" \'e\''}
        doc["pages"][0]["cells"][3]["attrs"] = {"meta_ref": 'x"<&>\'y'}
        pages = read_pages(render(doc))
        self.assertEqual(pages[0]["zero"].wrapper.get("owner"), 'a&b <c> "d" \'e\'')
        self.assertEqual(by_id(pages[0]["cells"])["p1:B1"].attrs["meta_ref"], 'x"<&>\'y')

    def test_secondary_label_at_negative_position(self):
        doc = full_doc()
        for c in doc["pages"][0]["cells"]:
            if c["id"] == "E1c":
                c["labels"][1]["pos"] = -1
        c = by_id(read_pages(render(doc))[0]["cells"])["p1:E1c:end"]
        self.assertEqual(c.geo.get("x"), "-1")

    def test_er_markers_are_unfilled_and_named_like_format_js(self):
        for sym, name in (("er-one", "ERone"), ("er-mandatory-one", "ERmandOne"), ("er-many", "ERmany"),
                          ("er-zero-one", "ERzeroToOne"), ("er-zero-many", "ERzeroToMany"), ("er-one-many", "ERoneToMany")):
            self.assertEqual(ST.ARROWS[sym], (name, 0, None))
        self.assertEqual(set(ST.ARROWS), set(S.ARROW_SYMBOLS))

    def test_dash_rule_line_over_role_over_default(self):
        cells = by_id(self.pages[0]["cells"])
        cases = {
            "p1:EA": ("0", None),                     # role line, no `line` -> solid
            "p1:E1c": ("1", "6 4"),                   # role dependency -> dashed
            "p1:E4c": ("1", "2 4"),                   # role return -> dotted
            "p1:E3c": ("1", "2 4"),                   # line dotted (explicit) on role line
        }
        for cid, (dashed, pattern) in cases.items():
            d = style_dict(cells[cid].style)
            self.assertEqual((d["dashed"], d.get("dashPattern")), (dashed, pattern), cid)
        # explicit `line` beats the role
        doc = full_doc()
        for c in doc["pages"][0]["cells"]:
            if c["id"] == "E1c":
                c["line"] = "solid"
        d = style_dict(by_id(read_pages(render(doc))[0]["cells"])["p1:E1c"].style)
        self.assertEqual((d["dashed"], d.get("dashPattern")), ("0", None))
        # markers never imply dashing: the `dependency` arrow on a solid line stays solid
        for c in doc["pages"][0]["cells"]:
            if c["id"] == "EA":
                c["end"] = "dependency"
        d = style_dict(by_id(read_pages(render(doc))[0]["cells"])["p1:EA"].style)
        self.assertEqual((d["endArrow"], d["dashed"]), ("open", "0"))

    def test_stroke_width_override_and_loop(self):
        cells = by_id(self.pages[0]["cells"])
        self.assertEqual(style_dict(cells["p1:E3c"].style)["strokeWidth"], "2")
        self.assertEqual(style_dict(cells["p1:EA"].style)["strokeWidth"], "1")
        self.assertEqual(style_dict(cells["p1:ELoop"].style)["orthogonalLoop"], "1")
        self.assertNotIn("orthogonalLoop", style_dict(cells["p1:EA"].style))

    def test_ports_use_four_decimals_not_fmt(self):
        doc = full_doc()
        doc["pages"][0]["cells"] = [
            {"id": "A", "type": "vertex", "x": 0, "y": 0, "w": 100, "h": 40},
            {"id": "B", "type": "vertex", "x": 300, "y": 0, "w": 100, "h": 40},
            {"id": "E", "type": "edge", "source": "A", "target": "B", "exit": {"x": 1, "y": 0.2525}, "entry": {"x": 0, "y": 0.75}}]
        d = style_dict(by_id(read_pages(render(doc))[0]["cells"])["p1:E"].style)
        self.assertEqual((d["exitX"], d["exitY"], d["exitDx"], d["exitDy"]), ("1", "0.2525", "0", "0"))
        self.assertEqual((d["entryX"], d["entryY"]), ("0", "0.75"))

    def test_style_raw_overrides_theme_once(self):
        cells = by_id(self.pages[1]["cells"])
        d = style_dict(cells["p2:X"].style)
        self.assertEqual((d["fontStyle"], d["strokeWidth"]), ("1", "3"))
        self.assertEqual(len([k for k, _ in parse_style(cells["p2:X"].style)[1] if k == "strokeWidth"]), 1)
        e = style_dict(cells["p2:E"].style)
        self.assertEqual((e["dashed"], e["dashPattern"], e["endSize"]), ("1", "1 1", "9"))

    def test_merge_raw_and_validate_pairs_units(self):
        self.assertEqual(ST.merge_raw([("a", "1"), ("b", "2")], "b=3;c=4"), [("a", "1"), ("b", "3"), ("c", "4")])
        self.assertEqual(ST.merge_raw([("a", "1")], None), [("a", "1")])
        with self.assertRaises(ValueError):
            ST.validate_pairs([("fooBar", "1")], "vertex")
        with self.assertRaises(ValueError):
            ST.validate_pairs([("exitDX", "0")], "edge")
        with self.assertRaises(ValueError):
            ST.validate_pairs([("html", "1")], "vertex")
        with self.assertRaises(ValueError):
            ST.validate_pairs([("fillColor", "1"), ("fillColor", "2")], "vertex")
        with self.assertRaises(ValueError):
            ST.validate_pairs([("swimlane", None)], "edge")


# ---- tables --------------------------------------------------------------------------------

class TableTest(unittest.TestCase):
    def setUp(self):
        self.pages = read_pages(render())
        self.cells = by_id(self.pages[0]["cells"])

    def test_swimlane_style_is_explicit(self):
        for tid in ("p1:T1", "p1:T5", "p1:T20", "p1:TP"):
            tokens, pairs = parse_style(self.cells[tid].style)
            d = dict(pairs)
            self.assertEqual(tokens, ["swimlane"])
            self.assertEqual(self.cells[tid].style.index("swimlane;"), 0)
            for k, v in (("childLayout", "stackLayout"), ("horizontal", "1"), ("startSize", str(S.TABLE_START_SIZE)),
                         ("horizontalStack", "0"), ("resizeParent", "1"), ("resizeParentMax", "0"),
                         ("resizeLast", "0"), ("collapsible", "0"), ("marginBottom", "0")):
                self.assertEqual(d[k], v, (tid, k))
            self.assertEqual(d["fillColor"], d["swimlaneFillColor"])

    def test_row_style(self):
        d = style_dict(self.cells["p1:T5:col1"].style)
        self.assertEqual(d["portConstraint"], "eastwest")
        self.assertEqual(d["points"], "[[0,0.5],[1,0.5]]")
        self.assertEqual((d["strokeColor"], d["fillColor"], d["align"], d["verticalAlign"]), ("none", "none", "left", "top"))
        self.assertNotIn("overflow", self.cells["p1:T5:col1"].style)
        self.assertEqual(parse_style(self.cells["p1:T5:col1"].style)[0], ["text"])
        sep = style_dict(self.cells["p1:T5:sep"].style)
        self.assertEqual(sep["shape"], "line")

    def test_table_titles_have_variant_prefix(self):
        self.assertEqual(self.cells["p1:T1"].value, "[NEW] mot_dong")
        self.assertEqual(self.cells["p1:T5"].value, "[EXTEND] nam_dong")
        self.assertEqual(self.cells["p1:T20"].value, "[REUSE] hai_muoi")
        self.assertEqual(self.cells["p1:TP"].value, "khong_variant")

    def test_geometry_invariants_and_fixed_point_of_stack_layout(self):
        start = S.TABLE_START_SIZE
        for tid in ("p1:T1", "p1:T5", "p1:T20", "p1:TP"):
            table = self.cells[tid]
            tw, th = num(table.geo.get("width")), num(table.geo.get("height"))
            rows = [c for c in self.pages[0]["cells"] if c.parent == tid]
            y = start
            kids = []
            for r in rows:
                g = r.geo
                self.assertEqual((num(g.get("x")), num(g.get("y")), num(g.get("width"))), (0, y, tw), r.id)
                y += num(g.get("height"))
                kids.append({"x": num(g.get("x")), "y": num(g.get("y")), "w": num(g.get("width")), "h": num(g.get("height"))})
            self.assertEqual(th, start + sum(k["h"] for k in kids), tid)
            out, pw, ph = stack_layout(tw, th, kids, start_size=start, horizontal=False,
                                       resize_parent=True, resize_parent_max=False, resize_last=False)
            self.assertEqual(out, kids, tid)
            self.assertEqual((pw, ph), (tw, th), tid)
        self.assertEqual(num(self.cells["p1:T5:nt"].geo.get("height")), 40)   # row keeps its own height
        self.assertEqual(num(self.cells["p1:T20"].geo.get("height")), start + 20 * S.TABLE_ROW_H)


# ---- edges against the draw.io simulation ------------------------------------------------

class EdgeSimulationTest(unittest.TestCase):
    """Re-derive end points from the XML alone and check SegmentConnector gives the written corners."""

    def abs_origin(self, cells, cid):
        x = y = 0.0
        while cid not in ("1", None):
            c = cells[cid]
            x += num(c.geo.get("x"))
            y += num(c.geo.get("y"))
            cid = c.parent
        return x, y

    def check_page(self, page):
        cells = by_id(page["cells"])
        checked = 0
        for e in page["cells"]:
            if not (e.edge and e.points):
                continue
            d = style_dict(e.style)
            ox, oy = self.abs_origin(cells, e.parent) if e.parent != "1" else (0.0, 0.0)

            def port(cid, prefix):
                c = cells[cid]
                cx, cy = self.abs_origin(cells, cid)
                return (cx + num(d[prefix + "X"]) * num(c.geo.get("width")) - ox,
                        cy + num(d[prefix + "Y"]) * num(c.geo.get("height")) - oy)

            p0, pn = port(e.source, "exit"), port(e.target, "entry")
            self.assertEqual(segment_connector(p0, pn, e.points), [p0] + e.points + [pn], e.id)
            checked += 1
        return checked

    def test_every_routed_edge(self):
        pages = read_pages(render())
        self.assertGreaterEqual(self.check_page(pages[0]), 7)   # incl. container-parent edges and a self-loop

    def test_edge_parent_is_lca_container(self):
        cells = by_id(read_pages(render())[0]["cells"])
        self.assertEqual(cells["p1:EIn2"].parent, "p1:C2")
        self.assertEqual(cells["p1:ECross"].parent, "p1:C")
        self.assertEqual(cells["p1:E1c"].parent, "1")

    def test_edge_labels(self):
        cells = by_id(read_pages(render())[0]["cells"])
        first = cells["p1:E1c"]
        self.assertEqual(first.value, "nhãn")
        self.assertEqual(first.geo.get("x"), "0.5")
        self.assertEqual(first.offset, (0.0, -8.0))
        self.assertEqual(first.geo.get("relative"), "1")
        second = cells["p1:E1c:end"]
        sd = style_dict(second.style)
        self.assertEqual(parse_style(second.style)[0], ["edgeLabel"])
        self.assertEqual((sd["connectable"], sd["resizable"]), ("0", "0"))
        self.assertTrue(second.vertex)
        self.assertEqual(second.value, "1..*")
        self.assertEqual(second.geo.get("relative"), "1")
        self.assertEqual(second.geo.get("x"), "1")
        self.assertEqual(cells["p1:EA"].value, "")
        self.assertIsNone(cells["p1:EA"].geo.get("x"))
        self.assertEqual(cells["p1:ELoop"].value, "tự nối")


# ---- themes --------------------------------------------------------------------------------

class ThemeTest(unittest.TestCase):
    def test_mono_colours_are_gray(self):
        for color in all_colors(render(theme="mono")):
            r, g, b = hex_to_rgb(color)
            self.assertTrue(r == g == b, color)

    def test_accent_adds_exactly_one_colour_and_marks_it(self):
        xml = render(theme="accent")
        non_gray = {c for c in all_colors(xml) if len(set(hex_to_rgb(c))) != 1}
        self.assertEqual(non_gray, {T.ACCENT_COLOR})
        used = 0
        for page in read_pages(xml):
            for c in page["cells"]:
                if c.style and T.ACCENT_COLOR in c.style:
                    used += 1
                    self.assertEqual(style_dict(c.style)["strokeWidth"], "2", c.id)
        self.assertGreater(used, 0)
        self.assertEqual(sum(1 for c in all_colors(render(theme="mono")) if c == T.ACCENT_COLOR), 0)

    def test_text_contrast(self):
        for theme in ("mono", "accent"):
            for page in read_pages(render(theme=theme)):
                for c in page["cells"]:
                    if not c.style:
                        continue
                    d = style_dict(c.style)
                    for bg in ("fillColor", "swimlaneFillColor"):
                        if d.get(bg, "none") != "none":
                            self.assertGreaterEqual(contrast(d["fontColor"], d[bg]), 4.5, (theme, c.id))
                    self.assertGreaterEqual(contrast(d["fontColor"], "#FFFFFF"), 4.5)

    def test_page_background_always_present(self):
        for theme in ("mono", "accent"):
            for page in read_pages(render(theme=theme)):
                self.assertEqual(page["model"].get("adaptiveColors"), "none")
                self.assertEqual(page["model"].get("background"), "#FFFFFF")

    # meaning must not rely on colour: two roles/variants must differ in a non-colour sign, or in
    # lightness by a margin that survives printing.
    def signs(self, pairs_and_tokens, title=""):
        tokens, pairs = pairs_and_tokens
        d = dict(pairs)
        shape = d.get("shape") or (tokens[0] if tokens else None)
        return {"shape": shape, "dashed": (d.get("dashed"), d.get("dashPattern")),
                "strokeWidth": d.get("strokeWidth"), "fontStyle": d.get("fontStyle"), "prefix": title}

    def distinct(self, a, b, gray_a=None, gray_b=None):
        sa, sb = self.signs(*a), self.signs(*b)
        if any(sa[k] != sb[k] for k in sa):
            return True
        return gray_a is not None and gray_b is not None and abs(lightness(gray_a) - lightness(gray_b)) >= 10

    def test_vertex_roles_differ_without_colour(self):
        roles = list(T.VERTEX_ROLE_STYLES)
        for theme in ("mono", "accent"):
            styled = {r: parse_style(ST.to_string(ST.vertex_style(theme, {"role": r}))) for r in roles}
            for i, a in enumerate(roles):
                for b in roles[i + 1:]:
                    self.assertTrue(self.distinct((styled[a],), (styled[b],)), (theme, a, b))

    def test_table_variants_differ_without_colour(self):
        variants = ("plain", "new", "extend", "reuse")
        for theme in ("mono", "accent"):
            styled, titles, grays = {}, {}, {}
            for v in variants:
                cell = {"variant": v, "title": "t"}
                styled[v] = parse_style(ST.to_string(ST.table_style(theme, cell)))
                titles[v] = ST.table_title(cell)
                grays[v] = style_dict(ST.to_string(ST.table_style(theme, cell)))["fillColor"]
            for i, a in enumerate(variants):
                for b in variants[i + 1:]:
                    sa, sb = self.signs(styled[a], titles[a]), self.signs(styled[b], titles[b])
                    self.assertTrue(any(sa[k] != sb[k] for k in sa) or abs(lightness(grays[a]) - lightness(grays[b])) >= 10, (a, b))
        # mono gray levels are far enough apart to survive printing
        self.assertGreaterEqual(lightness("#FFFFFF") - lightness("#E0E0E0"), 10)
        self.assertGreaterEqual(lightness("#E0E0E0") - lightness("#BDBDBD"), 10)

    def test_row_roles_and_edge_roles_differ(self):
        rows = {r: parse_style(ST.to_string(ST.row_style("mono", {"role": r}))) for r in S.ROW_ROLES}
        names = list(rows)
        for i, a in enumerate(names):
            for b in names[i + 1:]:
                self.assertTrue(self.distinct((rows[a],), (rows[b],)), (a, b))
        edges = {}
        for role in S.EDGE_ROLES:
            edge = {"role": role, "line": None, "stroke_width": None, "start": "none", "end": "classic",
                    "exit": None, "entry": None}
            edges[role] = parse_style(ST.to_string(ST.edge_style("mono", edge)))
        names = list(edges)
        for i, a in enumerate(names):
            for b in names[i + 1:]:
                self.assertTrue(self.distinct((edges[a],), (edges[b],)), (a, b))


class VariantValidationTest(unittest.TestCase):
    def test_variants_by_type(self):
        doc = full_doc()
        doc["pages"][0]["cells"][3]["variant"] = "new"        # vertex B1: only 'plain'
        with self.assertRaises(ValidationError) as ctx:
            validate_raw(doc)
        self.assertIn("variant", str(ctx.exception))
        doc = full_doc()
        for c in doc["pages"][0]["cells"]:
            if c["id"] == "T1":
                c["variant"] = "wow"
        with self.assertRaises(ValidationError):
            validate_raw(doc)


if __name__ == "__main__":
    unittest.main()
