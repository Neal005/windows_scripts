"""Serialise a normalised `raw` document to draw.io XML (uncompressed mxfile).

Built by string concatenation (not ElementTree) so attribute order and layout are fixed and
the output is byte-for-byte deterministic. Layout of one page:

  <mxfile><diagram id name><mxGraphModel ...><root>
    <object id="0" generator=... title=... ><mxCell/></object>    (cell "0", always an <object>)
    <mxCell id="1" parent="0"/>                                    (the layer)
    cells in JSON order; table rows follow their table; edge label children follow their edge

Ids: `<pageId>:<id>`, rows `<pageId>:<tableId>:<rowId>`, edge labels `<pageId>:<edgeId>:<labelId>`.
"""

from .. import GENERATOR
from ..core import ids, schema as S
from ..core.geometry import table_row_geometry
from ..core.numfmt import fmt
from . import styles as ST
from .escape import escape_attr

LAYER_ID = "1"
ROOT_ID = "0"


def _a(name, value):
    return ' %s="%s"' % (name, escape_attr(value))


def _n(value):
    return fmt(value)


class _Writer:
    def __init__(self):
        self.lines = []

    def add(self, depth, text):
        self.lines.append("  " * depth + text)


def _emit_cell(w, depth, cell_id, value, style, parent, extra, attrs, geometry_lines):
    """One cell. `extra` is a list of (name, value) attributes after parent (source/target/vertex/edge).

    With `attrs` the cell is wrapped in <object label=... attrs... id=...> and the inner mxCell
    carries no `value` (as in erd_mau_02.drawio).
    """
    tail = "".join(_a(k, v) for k, v in extra)
    if attrs:
        head = "<object" + _a("label", value) + "".join(_a(k, attrs[k]) for k in sorted(attrs)) + _a("id", cell_id) + ">"
        w.add(depth, head)
        w.add(depth + 1, "<mxCell" + _a("style", style) + _a("parent", parent) + tail + ">")
        for line in geometry_lines:
            w.add(depth + 2, line)
        w.add(depth + 1, "</mxCell>")
        w.add(depth, "</object>")
    else:
        w.add(depth, "<mxCell" + _a("id", cell_id) + _a("value", value) + _a("style", style)
              + _a("parent", parent) + tail + ">")
        for line in geometry_lines:
            w.add(depth + 1, line)
        w.add(depth, "</mxCell>")


def _geometry_rect(x, y, width, height):
    return ['<mxGeometry x="%s" y="%s" width="%s" height="%s" as="geometry"/>' % (_n(x), _n(y), _n(width), _n(height))]


def _label_geometry(label):
    """geometry of an edge label: x = position along the edge (-1..1), offset = absolute dx/dy."""
    return ['<mxGeometry x="%s" relative="1" as="geometry">' % _n(label["pos"]),
            '  <mxPoint x="%s" y="%s" as="offset"/>' % (_n(label["dx"]), _n(label["dy"])),
            "</mxGeometry>"]


def emit_document(doc, theme_name=None):
    """doc: normalised document from kinds.raw.validate_raw. Returns the XML text (LF, ends with LF)."""
    theme_name = ST.check_theme_name(theme_name or doc["theme"])
    theme = ST.T.THEMES[theme_name]
    w = _Writer()
    w.add(0, '<mxfile host="app.diagrams.net">')
    for page in doc["pages"]:
        _emit_page(w, doc, page, theme_name, theme)
    w.add(0, "</mxfile>")
    return "\n".join(w.lines) + "\n"


def _emit_page(w, doc, page, theme_name, theme):
    pid = page["id"]
    w.add(1, "<diagram" + _a("id", pid) + _a("name", page["name"]) + ">")
    w.add(2, '<mxGraphModel dx="0" dy="0" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" '
             'arrows="1" fold="1" page="1" pageScale="1"%s%s math="0" shadow="0"%s adaptiveColors="none">'
          % (_a("pageWidth", _n(page["width"])), _a("pageHeight", _n(page["height"])),
             _a("background", theme["page"])))
    w.add(3, "<root>")
    root_attrs = dict(doc["meta"])
    w.add(4, "<object" + _a("generator", GENERATOR) + _a("title", doc["title"])
          + "".join(_a(k, root_attrs[k]) for k in sorted(root_attrs)) + _a("id", ROOT_ID) + ">")
    w.add(5, "<mxCell/>")
    w.add(4, "</object>")
    w.add(4, '<mxCell id="%s" parent="%s"/>' % (LAYER_ID, ROOT_ID))

    def gid(local):
        return ids.cell_id(pid, local)

    def parent_of(local):
        return LAYER_ID if local is None else gid(local)

    for cell in page["cells"]:
        if cell["type"] == "vertex":
            style = ST.to_string(ST.validate_pairs(ST.merge_raw(ST.vertex_style(theme_name, cell), cell["style_raw"]), "vertex"))
            _emit_cell(w, 4, gid(cell["id"]), cell["label"], style, parent_of(cell["parent"]),
                       [("vertex", "1")], cell["attrs"],
                       _geometry_rect(cell["x"], cell["y"], cell["w"], cell["h"]))
        elif cell["type"] == "table":
            style = ST.to_string(ST.validate_pairs(ST.merge_raw(ST.table_style(theme_name, cell), cell["style_raw"]), "vertex"))
            tid = gid(cell["id"])
            _emit_cell(w, 4, tid, ST.table_title(cell), style, parent_of(cell["parent"]),
                       [("vertex", "1")], cell["attrs"],
                       _geometry_rect(cell["x"], cell["y"], cell["w"], cell["h"]))
            for row, geo in zip(cell["rows"], table_row_geometry(cell, S.TABLE_START_SIZE)):
                rstyle = ST.to_string(ST.validate_pairs(ST.row_style(theme_name, row), "vertex"))
                _emit_cell(w, 4, ids.child_id(tid, row["id"]), row["label"], rstyle, tid,
                           [("vertex", "1")], None, _geometry_rect(*geo))
        else:
            _emit_edge(w, pid, cell, theme_name, gid, parent_of)
    w.add(3, "</root>")
    w.add(2, "</mxGraphModel>")
    w.add(1, "</diagram>")


def _emit_edge(w, pid, edge, theme_name, gid, parent_of):
    style = ST.to_string(ST.validate_pairs(ST.merge_raw(ST.edge_style(theme_name, edge), edge["style_raw"]), "edge"))
    eid = gid(edge["id"])
    first = edge["labels"][0] if edge["labels"] else None
    geo = []
    opening = '<mxGeometry relative="1" as="geometry">'
    if first is not None:
        opening = '<mxGeometry x="%s" relative="1" as="geometry">' % _n(first["pos"])
    geo.append(opening)
    if edge["points"]:
        geo.append("  <Array as=\"points\">")
        for p in edge["points"]:
            geo.append('    <mxPoint x="%s" y="%s"/>' % (_n(p["x"]), _n(p["y"])))
        geo.append("  </Array>")
    if first is not None:
        geo.append('  <mxPoint x="%s" y="%s" as="offset"/>' % (_n(first["dx"]), _n(first["dy"])))
    geo.append("</mxGeometry>")
    _emit_cell(w, 4, eid, first["text"] if first else "", style, parent_of(edge["parent"]),
               [("source", gid(edge["source"])), ("target", gid(edge["target"])), ("edge", "1")],
               edge["attrs"], geo)
    for label in edge["labels"][1:]:
        lstyle = ST.to_string(ST.validate_pairs(ST.edge_label_style(theme_name), "vertex"))
        _emit_cell(w, 4, ids.child_id(eid, label["id"]), label["text"], lstyle, eid,
                   [("vertex", "1")], None, _label_geometry(label))
