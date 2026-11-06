"""Adapter for the project's `erd_mau_02.meta.json` format ("erd-meta-v1").

parse_erd_meta(data) -> model (plain dicts, deterministic order):

    {"title", "version", "tables": [table...], "relations": [relation...], "warnings": [str...]}
    table    = {"name", "kind" (NEW|EXTEND|REUSE), "variant" (new|extend|reuse), "rows": [row...],
                "text_width" (multiple of 40, 200..440), "title_label"}
    row      = {"id", "label", "role" (pk|fk|plain|note)}
    relation = {"id", "parent", "child", "fk_column", "label", "start", "end", "weight", "loop"}

build_raw_document(model, positions, widths=None, routes=None) -> dict in the INPUT schema of
kind `raw` (no h/loop/face keys, no None values): the caller runs validate_raw once and then
emit_document. Rules: plan/g1_erd_plan.md sections 2-3.
"""

from ..core.errors import ValidationError
from ..core.ids import is_valid_id, slug, unique_id

KINDS = ("NEW", "EXTEND", "REUSE")
VARIANT_OF = {"NEW": "new", "EXTEND": "extend", "REUSE": "reuse"}
TITLE_PREFIX = {"new": "[NEW] ", "extend": "[EXTEND] ", "reuse": "[REUSE] "}
SYMBOL = {"1": "er-mandatory-one", "0..1": "er-zero-one", "0..N": "er-zero-many", "1..N": "er-one-many"}
NOTE_LIMIT = 56
MIN_TEXT_WIDTH = 200
MAX_TEXT_WIDTH = 440
CELL_PADDING = 8            # spacingLeft + spacingRight of a row
BOLD_FACTOR = 1.08
SAFETY_FACTOR = 1.08
TOP_MARGIN = 100            # first table row of a layout starts at y >= TOP_MARGIN
LABEL_DY = -8

_NARROW = frozenset("ijltf.,:;()")   # plan 3.4; space and '=' count as 'other' (6.7 px, conservative)
_WIDE = frozenset("mwWM")


def is_erd_meta(data):
    """True for a document that looks like erd-meta-v1 (no `kind`, `tables`, `relationships`, schema "1")."""
    return (isinstance(data, dict) and "kind" not in data and isinstance(data.get("tables"), list)
            and isinstance(data.get("relationships"), list) and data.get("schema_version") == "1")


# ---- text measurement ---------------------------------------------------------------------

def text_px(text, bold=False):
    """Approximate width in px of `text` in Arial 12 (narrow 3.5, wide 10, other 6.7), bold x1.08."""
    total = 0.0
    for ch in text:
        if ch in _NARROW:
            total += 3.5
        elif ch in _WIDE:
            total += 10.0
        else:
            total += 6.7
    return total * (BOLD_FACTOR if bold else 1.0)


def _table_width(title, rows):
    widest = text_px(title, bold=True) + CELL_PADDING
    for row in rows:
        widest = max(widest, text_px(row["label"], bold=(row["role"] == "pk")) + CELL_PADDING)
    raw = widest * SAFETY_FACTOR
    width = 40 * int(-(-raw // 40))
    return max(MIN_TEXT_WIDTH, min(MAX_TEXT_WIDTH, width))


def _fit_label(label, bold, limit_px):
    """Cut `label` with a trailing '...' until it fits `limit_px` (usable text width)."""
    if text_px(label, bold) <= limit_px:
        return label
    cut = label
    while cut and text_px(cut + "...", bold) > limit_px:
        cut = cut[:-1]
    return cut + "..."


def _note(prefix, text):
    label = "%s %s" % (prefix, text)
    return label if len(label) <= NOTE_LIMIT else label[:NOTE_LIMIT - 3] + "..."


# ---- parsing -----------------------------------------------------------------------------

def _fail(path, message):
    raise ValidationError(message, path)


def _join(path, key):
    return "%s[%d]" % (path, key) if isinstance(key, int) else ("%s.%s" % (path, key) if path else key)


def _list(value, path):
    if not isinstance(value, list):
        _fail(path, "expected an array")
    return value


def _obj(value, path):
    if not isinstance(value, dict):
        _fail(path, "expected an object")
    return value


def _name(value, path):
    if not is_valid_id(value):
        _fail(path, "invalid name (1..200 chars, no whitespace, control chars or ':')")
    return value


def _str_list(value, path):
    out = []
    for i, item in enumerate(_list(value, path)):
        if not isinstance(item, str) or not item:
            _fail(_join(path, i), "expected a non-empty string")
        out.append(item)
    return out


def parse_erd_meta(data):
    d = _obj(data, "")
    if d.get("schema_version") != "1":
        _fail("schema_version", 'unsupported schema_version (expected the string "1")')
    tables_in = _list(d.get("tables"), "tables") if "tables" in d else _fail("tables", "missing required key 'tables'")
    rels_in = _list(d.get("relationships"), "relationships") if "relationships" in d \
        else _fail("relationships", "missing required key 'relationships'")
    warnings = []

    # 1. tables (first pass: raw facts), names unique
    infos = {}
    order = []
    for i, t in enumerate(tables_in):
        tp = _join("tables", i)
        t = _obj(t, tp)
        name = _name(t.get("name"), _join(tp, "name"))
        if name in infos:
            _fail(_join(tp, "name"), "duplicate table name '%s'" % name)
        kind = t.get("kind")
        if kind not in KINDS:
            _fail(_join(tp, "kind"), "must be one of: NEW, EXTEND, REUSE")
        cols = []
        for j, c in enumerate(_list(t.get("columns", []), _join(tp, "columns"))):
            cp = _join(_join(tp, "columns"), j)
            c = _obj(c, cp)
            cols.append({"name": _name(c.get("name"), _join(cp, "name")),
                         "type": c.get("pg_type") if isinstance(c.get("pg_type"), str) and c.get("pg_type") else "?",
                         "nullable": c.get("nullable") is True,
                         "change": c.get("change") if isinstance(c.get("change"), str) else None})
        pk = _str_list(t["primary_key"], _join(tp, "primary_key")) if "primary_key" in t else ["id"]
        if not pk:
            _fail(_join(tp, "primary_key"), "must not be empty")
        for j, col in enumerate(pk):
            _name(col, _join(_join(tp, "primary_key"), j))
        fk_cols = []
        for j, fk in enumerate(_list(t.get("foreign_keys", []), _join(tp, "foreign_keys"))):
            fp = _join(_join(tp, "foreign_keys"), j)
            fk_cols += _str_list(_obj(fk, fp).get("columns", []), _join(fp, "columns"))
        infos[name] = {"name": name, "kind": kind, "columns": cols, "pk": pk, "fk_declared": fk_cols,
                       "other_columns": bool(t.get("other_columns")),
                       "uniques": _keyed(t.get("uniques", []), _join(tp, "uniques"), "columns"),
                       "indexes": _keyed(t.get("indexes", []), _join(tp, "indexes"), "columns"),
                       "checks": _keyed(t.get("checks", []), _join(tp, "checks"), "expr")}
        order.append(name)

    # 2. relationships
    relations = []
    used_ids = set()
    derived_fk = {n: [] for n in order}
    for i, r in enumerate(rels_in):
        rp = _join("relationships", i)
        r = _obj(r, rp)
        parent, child = r.get("parent"), r.get("child")
        for key, value in (("parent", parent), ("child", child)):
            if not isinstance(value, str) or value not in infos:
                _fail(_join(rp, key), "unknown table %r" % (value,) if isinstance(value, str) else "expected a table name")
        fk_column = r.get("fk_column")
        if not isinstance(fk_column, str) or not fk_column:
            _fail(_join(rp, "fk_column"), "must be a non-empty string")
        _name(fk_column, _join(rp, "fk_column"))
        cards = []
        for key in ("parent_card", "child_card"):
            card = r.get(key)
            if not isinstance(card, str) or card not in SYMBOL:
                _fail(_join(rp, key), "must be one of: " + ", ".join(sorted(SYMBOL)))
            cards.append(card)
        label = r.get("label", "")
        if not isinstance(label, str):
            _fail(_join(rp, "label"), "expected a string")
        weight = 8 if cards[0] == "1" else (1 if cards[1] == "0..1" else 4)
        rid = unique_id("rel.%s.%s" % (child, fk_column), used_ids)
        relations.append({"id": rid, "parent": parent, "child": child, "fk_column": fk_column, "label": label,
                          "start": SYMBOL[cards[0]], "end": SYMBOL[cards[1]], "weight": weight,
                          "loop": parent == child})
        if fk_column not in derived_fk[child]:
            derived_fk[child].append(fk_column)

    # 3. FK declared without any relationship: still marked FK, warn
    for name in order:
        for col in infos[name]["fk_declared"]:
            if col not in derived_fk[name]:
                warnings.append("tables[%s]: foreign key column '%s' has no entry in relationships (no edge drawn)"
                                % (name, col))

    tables = [_build_table(infos[n], derived_fk[n]) for n in order]
    title = ""
    mau = d.get("mau")
    if isinstance(mau, dict) and isinstance(mau.get("ten_mau"), str):
        title = mau["ten_mau"]
    version = d.get("version") if isinstance(d.get("version"), str) else ""
    return {"title": title, "version": version, "tables": tables, "relations": relations, "warnings": warnings}


def _keyed(value, path, field):
    out = []
    for i, item in enumerate(_list(value, path)):
        ip = _join(path, i)
        item = _obj(item, ip)
        name = item.get("name") if isinstance(item.get("name"), str) and item.get("name") else "unnamed"
        raw = item.get(field)
        if isinstance(raw, list):
            raw = ", ".join(str(x) for x in raw)
        out.append((name, raw if isinstance(raw, str) else ""))
    return out


def _build_table(info, derived_fk):
    kind = info["kind"]
    variant = VARIANT_OF[kind]
    fk_set = set(info["fk_declared"]) | set(derived_fk)
    columns = {c["name"]: c for c in info["columns"]}

    def label_of(name, role, with_change):
        col = columns.get(name)
        text = "%s %s" % (name, col["type"] if col else "uuid")
        if col and col["nullable"]:
            text += " NULL"
        if with_change and col and col["change"]:
            text += " (%s)" % col["change"]
        if role == "pk":
            text += " PK" + (" FK" if name in fk_set else "")
        return text

    rows = []
    seen = set()

    def add(name, role, with_change=False):
        if name in seen:
            return
        seen.add(name)
        rows.append({"id": name, "label": label_of(name, role, with_change), "role": role})

    for name in info["pk"]:
        add(name, "pk", kind == "EXTEND")
    if kind == "NEW":
        for c in info["columns"]:
            add(c["name"], "fk" if c["name"] in fk_set else "plain")
    elif kind == "EXTEND":          # one pass in declaration order: FK columns and changed columns
        for c in info["columns"]:
            if c["name"] in fk_set or c["change"]:
                add(c["name"], "fk" if c["name"] in fk_set else "plain", True)
    for name in derived_fk:                       # FK columns derived from relationships (REUSE/EXTEND/NEW)
        add(name, "fk")
    for name in info["fk_declared"]:
        add(name, "fk")
    used = set(seen)
    if kind == "EXTEND" and info["other_columns"]:
        rows.append({"id": unique_id("other_columns", used), "label": "... cac cot khac khong doi", "role": "note"})
    for prefix, key, field in (("UK", "uniques", "uk"), ("IX", "indexes", "ix"), ("CK", "checks", "ck")):
        for name, detail in info[key]:
            text = ("%s(%s)" % (name, detail)) if key != "checks" else ("%s: %s" % (name, detail) if detail else name)
            rows.append({"id": unique_id("%s_%s" % (field, slug(name) or "x"), used),
                         "label": _note(prefix, text), "role": "note"})

    title_label = TITLE_PREFIX[variant] + info["name"]
    width = _table_width(title_label, rows)
    usable = width / SAFETY_FACTOR - CELL_PADDING
    for row in rows:
        row["label"] = _fit_label(row["label"], row["role"] == "pk", usable)
    return {"name": info["name"], "kind": kind, "variant": variant, "rows": rows, "text_width": width,
            "title_label": title_label}


# ---- raw document -------------------------------------------------------------------------

def build_raw_document(model, positions, widths=None, routes=None):
    """Build the INPUT-schema `raw` document for the model.

    positions: {table name: (x, y)}; widths: {table name: w} (default text_width);
    routes: {relation id: {"exit": {x, y}, "entry": {x, y}, "points": [{x, y}...]}} (optional per edge,
    mandatory for self-loops). Title and legend blocks sit above TOP_MARGIN.
    """
    widths = widths or {}
    routes = routes or {}
    cells = []
    title = model["title"] or "ERD"
    if model["version"]:
        title += " - " + model["version"]
    cells.append({"id": "erd_title", "type": "vertex", "role": "title", "x": 40, "y": 10, "w": 800, "h": 30,
                  "label": title})
    cells.append({"id": "erd_legend", "type": "vertex", "role": "note", "x": 40, "y": 48, "w": 800, "h": 30,
                  "label": "Chu thich: [NEW] trang | [EXTEND] xam nhat | [REUSE] xam dam"})
    for t in model["tables"]:
        x, y = positions[t["name"]]
        cells.append({"id": t["name"], "type": "table", "variant": t["variant"], "x": x, "y": y,
                      "w": widths.get(t["name"], t["text_width"]), "title": t["name"],
                      "rows": [dict(r) for r in t["rows"]], "attrs": {"entity": t["name"], "kind": t["kind"]}})
    for r in model["relations"]:
        edge = {"id": r["id"], "type": "edge", "source": r["parent"], "target": r["child"],
                "start": r["start"], "end": r["end"]}
        if r["label"]:
            edge["labels"] = [{"text": r["label"], "dy": LABEL_DY}]
        route = routes.get(r["id"])
        if route:
            edge["exit"], edge["entry"] = route["exit"], route["entry"]
            if route.get("points"):
                edge["points"] = [dict(p) for p in route["points"]]
        elif r["loop"]:
            raise ValueError("self-referencing relationship %s needs a route" % r["id"])
        cells.append(edge)
    return {"schema_version": 1, "kind": "raw", "title": title, "theme": "mono",
            "pages": [{"id": "erd", "name": "ERD", "cells": cells}]}
