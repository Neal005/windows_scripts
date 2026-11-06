"""Validator and normaliser for kind `raw` (Step 1: no emitting yet).

validate_raw(doc) -> RawResult(doc=<normalised dict>, warnings=<tuple of str>)
Raises ValidationError with an ASCII message and a field path such as
`pages[0].cells[3].points[1]: ...`. Rules: g0a1_plan.md sections 3 and 4.
"""

import math
from collections import namedtuple

from ..core import schema as S
from ..core.errors import ValidationError
from ..core.ids import is_valid_id, slug, unique_id
from ..core.text import find_bad_char, normalize_newlines

RawResult = namedtuple("RawResult", ["doc", "warnings"])

_DOC_KEYS = ("schema_version", "kind", "title", "theme", "meta", "pages")
_PAGE_KEYS = ("id", "name", "width", "height", "cells")
_COMMON_KEYS = ("id", "type", "role", "variant", "tags", "attrs", "style_raw")
_VERTEX_KEYS = _COMMON_KEYS + ("parent", "x", "y", "w", "h", "label")
_TABLE_KEYS = _COMMON_KEYS + ("parent", "x", "y", "w", "title", "rows")
_EDGE_KEYS = _COMMON_KEYS + (
    "parent", "line", "stroke_width", "source", "target", "exit", "entry", "points",
    "labels", "label", "start", "end",
)
_ROW_KEYS = ("id", "label", "role", "h")
_LABEL_KEYS = ("id", "text", "pos", "dx", "dy")


def join(path, key):
    if isinstance(key, int):
        return "%s[%d]" % (path, key)
    return "%s.%s" % (path, key) if path else key


def fail(path, message):
    raise ValidationError(message, path)


def validate_raw(doc):
    v = _Validator()
    out = v.document(doc)
    return RawResult(out, tuple(v.warnings))


class _Validator:
    def __init__(self):
        self.warnings = []

    # ---- primitive checks -------------------------------------------------

    def obj(self, value, path, allowed, required=()):
        if not isinstance(value, dict):
            fail(path, "expected an object")
        for key in sorted(value):
            if key not in allowed:
                fail(join(path, key), "unknown key")
        for key in required:
            if key not in value:
                fail(path, "missing required key '%s'" % key)
        return value

    def num(self, value, path, positive=False, lo=None, hi=None, decimals=None):
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            fail(path, "expected a number")
        if isinstance(value, float) and not math.isfinite(value):
            fail(path, "number must be finite")
        if abs(value) > S.COORD_LIMIT:
            fail(path, "number out of range (limit %d)" % S.COORD_LIMIT)
        if decimals is not None:
            scale = 10 ** decimals
            if abs(value * scale - round(value * scale)) > 1e-6:
                fail(path, "at most %d decimal digit(s) allowed (output precision)" % decimals)
        if positive and value <= 0:
            fail(path, "must be > 0")
        if lo is not None and value < lo:
            fail(path, "must be >= %s" % lo)
        if hi is not None and value > hi:
            fail(path, "must be <= %s" % hi)
        return value

    def text(self, value, path, allow_empty=False, maxlen=4000):
        if not isinstance(value, str):
            fail(path, "expected a string")
        value = normalize_newlines(value)
        bad = find_bad_char(value)
        if bad is not None:
            fail(path, "control character U+%04X at index %d is not allowed" % (ord(bad[1]), bad[0]))
        if not allow_empty and value == "":
            fail(path, "must not be empty")
        if len(value) > maxlen:
            fail(path, "string longer than %d characters" % maxlen)
        return value

    def ident(self, value, path):
        if not is_valid_id(value):
            fail(path, "invalid id (1..200 chars, no whitespace, control chars or ':')")
        return value

    def choice(self, value, options, path):
        if not isinstance(value, str) or value not in options:
            fail(path, "must be one of: %s" % ", ".join(options))
        return value

    def lst(self, value, path, nonempty=False):
        if not isinstance(value, list):
            fail(path, "expected an array")
        if nonempty and not value:
            fail(path, "must not be empty")
        return value

    def variant(self, d, path):
        if "variant" not in d:
            return None
        value = d["variant"]
        if not isinstance(value, str) or not S.VARIANT_RE.match(value):
            fail(join(path, "variant"), "must match [a-z][a-z0-9_-]{0,31}")
        return value

    def tags(self, d, path):
        value = self.lst(d.get("tags", []), join(path, "tags"))
        out = []
        for i, tag in enumerate(value):
            if not isinstance(tag, str) or not S.TAG_RE.match(tag):
                fail(join(join(path, "tags"), i), "tag must match [A-Za-z0-9_.-]{1,64}")
            out.append(tag)
        return out

    def attrs(self, value, path, forbid=()):
        if not isinstance(value, dict):
            fail(path, "expected an object")
        out = {}
        for key in sorted(value):
            kp = join(path, key)
            if not S.ATTR_KEY_RE.match(key):
                fail(kp, "attribute name must match [A-Za-z_][A-Za-z0-9_.-]{0,63}")
            if key in S.RESERVED_ATTR_KEYS:
                fail(kp, "attribute name '%s' is reserved" % key)
            if key.lower().startswith("xml"):
                fail(kp, "attribute names starting with 'xml' are reserved by XML")
            if key in forbid:
                fail(kp, "attribute '%s' is written by the tool and cannot be set here" % key)
            out[key] = self.text(value[key], kp, allow_empty=True)
        return out

    def style_raw(self, d, path, kind):
        if "style_raw" not in d:
            return None
        sp = join(path, "style_raw")
        value = self.text(d["style_raw"], sp)
        keys = S.VERTEX_STYLE_KEYS if kind == "vertex" else S.EDGE_STYLE_KEYS
        bare = S.VERTEX_STYLE_BARE if kind == "vertex" else S.EDGE_STYLE_BARE
        seen = set()
        parts = []
        for seg in value.split(";"):
            seg = seg.strip()
            if not seg:
                continue
            if "=" not in seg:
                if seg not in bare:
                    fail(sp, "style token '%s' is not allowed" % seg)
                key, val = seg, None
            else:
                key, val = [s.strip() for s in seg.split("=", 1)]
                if key == "html":
                    fail(sp, "key 'html' is not allowed (labels are plain text, html=0)")
                if not S.STYLE_KEY_RE.match(key) or key not in keys:
                    fail(sp, "style key '%s' is not allowed for a %s" % (key, kind))
                if val == "":
                    fail(sp, "style key '%s' has an empty value" % key)
            if key in seen:
                fail(sp, "duplicate style key '%s'" % key)
            seen.add(key)
            parts.append(key if val is None else "%s=%s" % (key, val))
        if not parts:
            fail(sp, "style_raw has no entries")
        self.warnings.append("%s: style_raw overrides the theme style" % sp)
        return ";".join(parts)

    # ---- document / page --------------------------------------------------

    def document(self, doc):
        d = self.obj(doc, "", _DOC_KEYS, ("schema_version", "kind", "pages"))
        sv = d["schema_version"]
        if isinstance(sv, bool) or not isinstance(sv, int) or sv != S.SCHEMA_VERSION:
            fail("schema_version", "unsupported schema_version (expected %d)" % S.SCHEMA_VERSION)
        if d["kind"] != "raw":
            fail("kind", "this validator handles kind 'raw'")
        theme = self.choice(d.get("theme", "mono"), S.THEMES, "theme") if "theme" in d else "mono"
        meta = {}
        if "meta" in d:
            meta = self.attrs(d["meta"], "meta", forbid=("generator", "title"))
        pages_in = self.lst(d["pages"], "pages", nonempty=True)
        pages = []
        page_ids = set()
        for i, page in enumerate(pages_in):
            norm = self.page(page, join("pages", i), i)
            if norm["id"] in page_ids:
                fail(join(join("pages", i), "id"), "duplicate page id '%s'" % norm["id"])
            page_ids.add(norm["id"])
            pages.append(norm)
        title = self.text(d["title"], "title") if "title" in d else pages[0]["name"]
        return {
            "schema_version": S.SCHEMA_VERSION, "kind": "raw", "title": title,
            "theme": theme, "meta": meta, "pages": pages,
        }

    def page(self, page, path, index):
        d = self.obj(page, path, _PAGE_KEYS, ("id", "cells"))
        pid = self.ident(d["id"], join(path, "id"))
        name = self.text(d["name"], join(path, "name")) if "name" in d else "Trang %d" % (index + 1)
        width = self.num(d["width"], join(path, "width"), positive=True, decimals=1) if "width" in d else None
        height = self.num(d["height"], join(path, "height"), positive=True, decimals=1) if "height" in d else None
        cells_path = join(path, "cells")
        raw_cells = self.lst(d["cells"], cells_path)

        cells = []
        by_id = {}
        for i, cell in enumerate(raw_cells):
            cp = join(cells_path, i)
            if not isinstance(cell, dict):
                fail(cp, "expected an object")
            ctype = self.choice(cell.get("type"), ("vertex", "table", "edge"), join(cp, "type")) \
                if "type" in cell else fail(cp, "missing required key 'type'")
            if ctype == "vertex":
                norm = self.vertex(cell, cp)
            elif ctype == "table":
                norm = self.table(cell, cp)
            else:
                norm = self.edge_fields(cell, cp)
            norm["_path"] = cp
            if norm["id"] in by_id:
                fail(join(cp, "id"), "duplicate cell id '%s'" % norm["id"])
            by_id[norm["id"]] = norm
            cells.append(norm)

        self.resolve_parents(cells, by_id)
        origins = {}
        for cell in cells:
            if cell["type"] != "edge":
                self.check_containment(cell, by_id)
        for cell in cells:
            if cell["type"] == "edge":
                self.resolve_edge(cell, by_id, origins)
        if width is None or height is None:
            auto_w, auto_h = self.auto_size(cells, by_id, origins)
            width = auto_w if width is None else width
            height = auto_h if height is None else height
        for cell in cells:
            del cell["_path"]
        return {"id": pid, "name": name, "width": width, "height": height, "cells": cells}

    # ---- cells (field level) ----------------------------------------------

    def common(self, d, path, default_role, roles):
        out = {
            "id": self.ident(d["id"], join(path, "id")),
            "role": self.choice(d.get("role", default_role), roles, join(path, "role")),
            "variant": self.variant(d, path),
            "tags": self.tags(d, path),
            "attrs": self.attrs(d["attrs"], join(path, "attrs")) if "attrs" in d else {},
        }
        return out

    def parent_field(self, d, path):
        if "parent" not in d:
            return None
        return self.ident(d["parent"], join(path, "parent"))

    def vertex(self, c, path):
        d = self.obj(c, path, _VERTEX_KEYS, ("id", "type", "x", "y", "w", "h"))
        out = self.common(d, path, "box", S.VERTEX_ROLES)
        out.update({
            "type": "vertex",
            "parent": self.parent_field(d, path),
            "x": self.num(d["x"], join(path, "x"), decimals=1),
            "y": self.num(d["y"], join(path, "y"), decimals=1),
            "w": self.num(d["w"], join(path, "w"), positive=True, decimals=1),
            "h": self.num(d["h"], join(path, "h"), positive=True, decimals=1),
            "label": self.text(d.get("label", ""), join(path, "label"), allow_empty=True),
            "style_raw": self.style_raw(d, path, "vertex"),
        })
        return out

    def table(self, c, path):
        if "h" in c:
            fail(join(path, "h"), "table height is computed from its rows; remove 'h'")
        d = self.obj(c, path, _TABLE_KEYS, ("id", "type", "x", "y", "w", "title", "rows"))
        out = self.common(d, path, "table", S.TABLE_ROLES)
        rows = self.rows(d["rows"], join(path, "rows"))
        out.update({
            "type": "table",
            "parent": self.parent_field(d, path),
            "x": self.num(d["x"], join(path, "x"), decimals=1),
            "y": self.num(d["y"], join(path, "y"), decimals=1),
            "w": self.num(d["w"], join(path, "w"), positive=True, decimals=1),
            "title": self.text(d["title"], join(path, "title")),
            "rows": rows,
            "h": S.TABLE_START_SIZE + sum(r["h"] for r in rows),
            "style_raw": self.style_raw(d, path, "vertex"),
        })
        return out

    def rows(self, value, path):
        items = self.lst(value, path, nonempty=True)
        parsed = []
        explicit = set()
        for i, r in enumerate(items):
            rp = join(path, i)
            if isinstance(r, str):
                parsed.append({"id": None, "label": self.text(r, rp), "role": "plain", "h": S.TABLE_ROW_H})
                continue
            d = self.obj(r, rp, _ROW_KEYS)
            role = self.choice(d.get("role", "plain"), S.ROW_ROLES, join(rp, "role"))
            if "label" not in d and role != "separator":
                fail(rp, "missing required key 'label'")
            label = self.text(d.get("label", ""), join(rp, "label"), allow_empty=(role == "separator"))
            height = self.num(d["h"], join(rp, "h"), positive=True, decimals=1) if "h" in d else S.TABLE_ROW_H
            rid = None
            if "id" in d:
                rid = self.ident(d["id"], join(rp, "id"))
                if rid in explicit:
                    fail(join(rp, "id"), "duplicate row id '%s'" % rid)
                explicit.add(rid)
            parsed.append({"id": rid, "label": label, "role": role, "h": height})
        used = set(explicit)
        for r in parsed:
            if r["id"] is None:
                r["id"] = unique_id(slug(r["label"])[:100] or "row", used)
        return parsed

    def point(self, value, path):
        d = self.obj(value, path, ("x", "y"), ("x", "y"))
        return {"x": self.num(d["x"], join(path, "x"), decimals=1),
                "y": self.num(d["y"], join(path, "y"), decimals=1)}

    def port(self, value, path):
        d = self.obj(value, path, ("x", "y"), ("x", "y"))
        x = self.num(d["x"], join(path, "x"), lo=0, hi=1, decimals=S.PORT_DECIMALS)
        y = self.num(d["y"], join(path, "y"), lo=0, hi=1, decimals=S.PORT_DECIMALS)
        on_x = x in (0, 1)
        on_y = y in (0, 1)
        if on_x and on_y:
            fail(path, "port on a block corner is ambiguous (the attached side cannot be determined)")
        if not (on_x or on_y):
            fail(path, "port must lie on the block boundary (x or y equal to 0 or 1)")
        if on_x:
            face = "left" if x == 0 else "right"
        else:
            face = "top" if y == 0 else "bottom"
        return {"x": x, "y": y, "face": face}

    def edge_labels(self, d, path):
        if "label" in d and "labels" in d:
            fail(path, "use either 'label' or 'labels', not both")
        if "label" in d:
            text = self.text(d["label"], join(path, "label"))
            return [{"id": None, "text": text, "pos": 0, "dx": 0, "dy": 0}]
        lp = join(path, "labels")
        items = self.lst(d.get("labels", []), lp)
        out = []
        seen = set()
        for i, item in enumerate(items):
            ip = join(lp, i)
            ld = self.obj(item, ip, _LABEL_KEYS, ("text",))
            lid = None
            if "id" in ld:
                lid = self.ident(ld["id"], join(ip, "id"))
                if lid in seen:
                    fail(join(ip, "id"), "duplicate label id '%s'" % lid)
                seen.add(lid)
            elif i > 0:
                fail(ip, "labels after the first need an explicit 'id'")
            out.append({
                "id": lid,
                "text": self.text(ld["text"], join(ip, "text")),
                "pos": self.num(ld["pos"], join(ip, "pos"), lo=-1, hi=1, decimals=1) if "pos" in ld else 0,
                "dx": self.num(ld["dx"], join(ip, "dx"), decimals=1) if "dx" in ld else 0,
                "dy": self.num(ld["dy"], join(ip, "dy"), decimals=1) if "dy" in ld else 0,
            })
        return out

    def edge_fields(self, c, path):
        d = self.obj(c, path, _EDGE_KEYS, ("id", "type", "source", "target"))
        out = self.common(d, path, "line", S.EDGE_ROLES)
        points = []
        if "points" in d:
            pp = join(path, "points")
            points = [self.point(p, join(pp, i)) for i, p in enumerate(self.lst(d["points"], pp))]
        out.update({
            "type": "edge",
            "parent": self.parent_field(d, path),
            "line": self.choice(d["line"], S.LINE_STYLES, join(path, "line")) if "line" in d else None,
            "stroke_width": self.num(d["stroke_width"], join(path, "stroke_width"), positive=True, hi=100, decimals=1)
            if "stroke_width" in d else None,
            "source": self.ident(d["source"], join(path, "source")),
            "target": self.ident(d["target"], join(path, "target")),
            "exit": self.port(d["exit"], join(path, "exit")) if "exit" in d else None,
            "entry": self.port(d["entry"], join(path, "entry")) if "entry" in d else None,
            "points": points,
            "labels": self.edge_labels(d, path),
            "start": self.choice(d.get("start", S.DEFAULT_START), S.ARROW_SYMBOLS, join(path, "start")),
            "end": self.choice(d.get("end", S.DEFAULT_END), S.ARROW_SYMBOLS, join(path, "end")),
            "style_raw": self.style_raw(d, path, "edge"),
        })
        return out

    # ---- references and geometry ------------------------------------------

    def resolve_parents(self, cells, by_id):
        for cell in cells:
            if cell["type"] == "edge":
                continue
            pid = cell["parent"]
            if pid is None:
                continue
            pp = join(cell["_path"], "parent")
            parent = by_id.get(pid)
            if parent is None:
                fail(pp, "unknown cell '%s'" % pid)
            if parent["type"] != "vertex" or parent["role"] != "container":
                fail(pp, "parent '%s' must be a vertex with role 'container'" % pid)
        for cell in cells:
            if cell["type"] == "edge":
                continue
            seen = {cell["id"]}
            cur = cell["parent"]
            while cur is not None:
                if cur in seen:
                    fail(join(cell["_path"], "parent"), "parent chain forms a cycle")
                seen.add(cur)
                cur = by_id[cur]["parent"]

    def origin(self, cell_id, by_id, cache):
        """Absolute (x, y) of the top-left corner of a vertex/table, or (0, 0) for None."""
        if cell_id is None:
            return (0, 0)
        if cell_id in cache:
            return cache[cell_id]
        cell = by_id[cell_id]
        px, py = self.origin(cell["parent"], by_id, cache)
        cache[cell_id] = (px + cell["x"], py + cell["y"])
        return cache[cell_id]

    def check_containment(self, cell, by_id):
        pid = cell["parent"]
        if pid is None:
            if cell["x"] < 0 or cell["y"] < 0:
                fail(cell["_path"], "top-level blocks must have x >= 0 and y >= 0")
            return
        parent = by_id[pid]
        eps = 1e-9
        if (cell["x"] < -eps or cell["y"] < -eps or cell["x"] + cell["w"] > parent["w"] + eps
                or cell["y"] + cell["h"] > parent["h"] + eps):
            fail(cell["_path"], "block lies outside its parent container '%s' "
                 "(child coordinates are relative to the parent)" % pid)

    def chain(self, cid, by_id, include_self):
        """Container ancestors usable as an edge parent, innermost first."""
        cell = by_id[cid]
        out = []
        if include_self and cell["type"] == "vertex" and cell["role"] == "container":
            out.append(cid)
        cur = cell["parent"]
        while cur is not None:
            out.append(cur)
            cur = by_id[cur]["parent"]
        return out

    def resolve_edge(self, edge, by_id, cache):
        path = edge["_path"]
        for field in ("source", "target"):
            ref = by_id.get(edge[field])
            if ref is None:
                fail(join(path, field), "unknown cell '%s'" % edge[field])
            if ref["type"] == "edge":
                fail(join(path, field), "an edge cannot connect to another edge")
        src = by_id[edge["source"]]
        tgt = by_id[edge["target"]]
        loop = edge["source"] == edge["target"]
        src_chain = self.chain(src["id"], by_id, not loop)
        tgt_chain = self.chain(tgt["id"], by_id, not loop)
        declared = edge["parent"]
        if declared is None:
            tgt_set = set(tgt_chain)
            parent = next((c for c in src_chain if c in tgt_set), None)
        else:
            pp = join(path, "parent")
            if declared not in by_id:
                fail(pp, "unknown cell '%s'" % declared)
            if declared not in src_chain or declared not in tgt_chain:
                fail(pp, "parent must be a container that is an ancestor of both ends")
            parent = declared
        edge["parent"] = parent
        edge["loop"] = loop
        if loop and len(edge["points"]) < 2:
            fail(path, "a self-connecting edge needs at least 2 points")
        self.check_route(edge, src, tgt, by_id, cache)

    def check_route(self, edge, src, tgt, by_id, cache):
        path = edge["_path"]
        pts = edge["points"]
        ex, en = edge["exit"], edge["entry"]
        if not pts:
            return
        if ex is None:
            fail(join(path, "exit"), "required when 'points' is given (needed to align the first point)")
        if en is None:
            fail(join(path, "entry"), "required when 'points' is given (needed to align the last point)")
        ox, oy = self.origin(edge["parent"], by_id, cache)

        def port_xy(cell, port):
            cx, cy = self.origin(cell["id"], by_id, cache)
            return (cx + port["x"] * cell["w"] - ox, cy + port["y"] * cell["h"] - oy)

        p_exit = port_xy(src, ex)
        p_entry = port_xy(tgt, en)
        eps = S.ALIGN_EPS

        def check_end(point, port_pt, face, ppath, what):
            horizontal = face in ("left", "right")
            off_axis = abs(point["y"] - port_pt[1]) if horizontal else abs(point["x"] - port_pt[0])
            along = abs(point["x"] - port_pt[0]) if horizontal else abs(point["y"] - port_pt[1])
            if off_axis > eps:
                axis = "y" if horizontal else "x"
                want = port_pt[1] if horizontal else port_pt[0]
                fail(ppath, "not aligned with the %s port on the %s side (expected %s = %s)"
                     % (what, face, axis, _show(want)))
            if along < S.MIN_SEGMENT:
                fail(ppath, "closer than %d px to the %s port (segment too short)" % (S.MIN_SEGMENT, what))

        base = join(path, "points")
        check_end(pts[0], p_exit, ex["face"], join(base, 0), "exit")
        for i in range(1, len(pts)):
            dx = abs(pts[i]["x"] - pts[i - 1]["x"])
            dy = abs(pts[i]["y"] - pts[i - 1]["y"])
            ip = join(base, i)
            if dx > eps and dy > eps:
                fail(ip, "diagonal segment: consecutive points must share x or y")
            if max(dx, dy) < S.MIN_SEGMENT:
                fail(ip, "segment shorter than %d px (draw.io drops points closer than 1 px)" % S.MIN_SEGMENT)
        check_end(pts[-1], p_entry, en["face"], join(base, len(pts) - 1), "entry")

    def auto_size(self, cells, by_id, origins):
        right = 0
        bottom = 0
        found = False
        for cell in cells:
            if cell["type"] == "edge":
                ox, oy = self.origin(cell["parent"], by_id, origins)
                for p in cell["points"]:
                    right = max(right, ox + p["x"])
                    bottom = max(bottom, oy + p["y"])
                    found = True
            else:
                ox, oy = self.origin(cell["id"], by_id, origins)
                right = max(right, ox + cell["w"])
                bottom = max(bottom, oy + cell["h"])
                found = True
        if not found:
            return S.DEFAULT_PAGE_W, S.DEFAULT_PAGE_H
        return (_ceil10(right + S.PAGE_MARGIN), _ceil10(bottom + S.PAGE_MARGIN))


def _ceil10(value):
    return int(math.ceil(value / 10.0)) * 10


def _show(value):
    if isinstance(value, float) and value == int(value):
        return str(int(value))
    return str(value)
