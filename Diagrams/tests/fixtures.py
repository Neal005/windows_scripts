"""Shared documents for emitter tests (and, later, the smoke example)."""

from diagram_tool.core import schema as S


def pt(x, y):
    return {"x": x, "y": y}


def rows(n, prefix="col"):
    out = []
    for i in range(n):
        role = "pk" if i == 0 else ("fk" if i == 1 else "plain")
        out.append({"id": "%s%d" % (prefix, i), "label": "%s%d varchar" % (prefix, i), "role": role})
    return out


def full_doc():
    cells = [
        {"id": "ttl", "type": "vertex", "role": "title", "x": 40, "y": 10, "w": 400, "h": 30, "label": "Tiêu đề"},
        {"id": "C", "type": "vertex", "role": "container", "x": 40, "y": 60, "w": 800, "h": 500, "label": "Nhóm ngoài"},
        {"id": "C2", "type": "vertex", "role": "container", "parent": "C", "x": 30, "y": 40, "w": 400, "h": 300, "label": "Nhóm trong"},
        {"id": "B1", "type": "vertex", "parent": "C2", "x": 20, "y": 40, "w": 120, "h": 50, "label": "Khối B1",
         "attrs": {"meta_ref": "x.y", "entity": "b1"}},
        {"id": "B2", "type": "vertex", "parent": "C2", "x": 240, "y": 40, "w": 120, "h": 50,
         "label": "a <=> b\nList<Entity> & \"q\" 'r'", "variant": "plain", "tags": ["x", "y"]},
        {"id": "B3", "type": "vertex", "parent": "C", "x": 500, "y": 40, "w": 100, "h": 50, "label": "B3"},
        {"id": "N", "type": "vertex", "role": "note", "x": 900, "y": 60, "w": 200, "h": 60, "label": "Ghi chú: Đường"},
        {"id": "TX", "type": "vertex", "role": "text", "x": 900, "y": 140, "w": 200, "h": 30, "label": "Chữ"},
        {"id": "T1", "type": "table", "variant": "new", "x": 900, "y": 200, "w": 220, "title": "mot_dong", "rows": rows(1)},
        {"id": "T5", "type": "table", "variant": "extend", "x": 900, "y": 300, "w": 220, "title": "nam_dong",
         "rows": rows(4) + [{"id": "sep", "label": "", "role": "separator"}, {"id": "nt", "label": "ghi chu", "role": "note", "h": 40}],
         "attrs": {"meta_ref": "t5"}},
        {"id": "T20", "type": "table", "variant": "reuse", "x": 1200, "y": 40, "w": 220, "title": "hai_muoi", "rows": rows(20, "c")},
        {"id": "TP", "type": "table", "x": 1200, "y": 700, "w": 220, "title": "khong_variant", "rows": ["a", "b"]},
        {"id": "S1", "type": "vertex", "x": 40, "y": 600, "w": 100, "h": 40, "label": "S1"},
        {"id": "S2", "type": "vertex", "x": 400, "y": 700, "w": 100, "h": 40, "label": "S2"},
        # edges ----------------------------------------------------------------
        {"id": "EA", "type": "edge", "source": "S1", "target": "S2"},
        {"id": "E1c", "type": "edge", "role": "dependency", "source": "S1", "target": "S2", "end": "open",
         "exit": {"x": 1, "y": 0.5}, "entry": {"x": 0.5, "y": 0}, "points": [pt(450, 620)],
         "labels": [{"text": "nhãn", "pos": 0.5, "dy": -8}, {"id": "end", "text": "1..*", "pos": 1}]},
        {"id": "E2c", "type": "edge", "source": "S1", "target": "S2", "start": "er-one-many", "end": "er-zero-many",
         "exit": {"x": 0.5, "y": 1}, "entry": {"x": 0.5, "y": 1}, "points": [pt(90, 800), pt(450, 800)]},
        {"id": "E3c", "type": "edge", "source": "S1", "target": "S2", "line": "dotted", "stroke_width": 2,
         "exit": {"x": 0.5, "y": 1}, "entry": {"x": 0, "y": 0.5}, "points": [pt(90, 690), pt(300, 690), pt(300, 720)]},
        {"id": "E4c", "type": "edge", "source": "S1", "target": "S2", "role": "return",
         "exit": {"x": 1, "y": 0.5}, "entry": {"x": 0, "y": 0.5},
         "points": [pt(200, 620), pt(200, 670), pt(300, 670), pt(300, 720)]},
        {"id": "ELoop", "type": "edge", "source": "S2", "target": "S2", "label": "tự nối",
         "exit": {"x": 1, "y": 0.25}, "entry": {"x": 1, "y": 0.75}, "points": [pt(540, 710), pt(540, 730)]},
        {"id": "EIn", "type": "edge", "source": "B1", "target": "B2", "label": "trong nhom"},
        {"id": "EIn2", "type": "edge", "source": "B1", "target": "B2",
         "exit": {"x": 0.5, "y": 1}, "entry": {"x": 0.5, "y": 1}, "points": [pt(80, 130), pt(300, 130)]},
        {"id": "ECross", "type": "edge", "source": "B1", "target": "B3",
         "exit": {"x": 0.5, "y": 1}, "entry": {"x": 0.5, "y": 1}, "points": [pt(110, 200), pt(550, 200)]},
        {"id": "ETab", "type": "edge", "source": "T1", "target": "T5", "start": "inherit", "end": "aggregation"},
    ]
    for i, sym in enumerate(S.ARROW_SYMBOLS):
        y = 40 + i * 60
        cells.append({"id": "L%d" % i, "type": "vertex", "x": 1500, "y": y, "w": 80, "h": 30, "label": "L%d" % i})
        cells.append({"id": "R%d" % i, "type": "vertex", "x": 1700, "y": y, "w": 80, "h": 30, "label": "R%d" % i})
        cells.append({"id": "A%d" % i, "type": "edge", "source": "L%d" % i, "target": "R%d" % i,
                      "start": sym, "end": sym, "label": sym})
    return {
        "schema_version": 1, "kind": "raw", "title": "Tong hop", "theme": "mono", "meta": {"owner": "team"},
        "pages": [
            {"id": "p1", "name": "Trang 1", "cells": cells},
            {"id": "p2", "name": "Trang 2", "width": 600, "height": 400, "cells": [
                {"id": "X", "type": "vertex", "x": 40, "y": 40, "w": 120, "h": 50, "label": "X",
                 "style_raw": "fontStyle=1;strokeWidth=3"},
                {"id": "Y", "type": "vertex", "x": 300, "y": 40, "w": 120, "h": 50, "label": "Y"},
                {"id": "E", "type": "edge", "source": "X", "target": "Y", "attrs": {"meta_ref": "rel1"},
                 "style_raw": "dashed=1;dashPattern=1 1;endSize=9"},
            ]},
        ],
    }
