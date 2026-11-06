"""Explicit draw.io style strings: marker table, allowed key lists, per-cell builders.

A style is a list of (key, value) pairs; a bare leading token (swimlane, text, edgeLabel)
is a pair with value None. Everything the theme decides is written explicitly (colours,
font, arrows with fill, header size, dashes) so draw.io defaults never leak in.
"""

from ..core import schema as S
from ..core.errors import ValidationError
from ..core.numfmt import fmt, fmt_ratio
from . import themes as T

# symbol -> (arrow, fill, size or None). Fill is explicit per end (draw.io default is fill=1).
# ER markers: Format.js:165-170 (fill 0). inherit/realize: block + endFill=0 + size 16.
# aggregation/composition: diamondThin (Format.js:149,157) fill 0/1, size 24.
# dependency: the `open` marker only; the dashed line comes from `line`/role, not from the marker.
ARROWS = {
    "none": ("none", 0, None),
    "classic": ("classic", 1, None),
    "open": ("open", 0, None),
    "block": ("block", 1, None),
    "block-open": ("block", 0, None),
    "diamond": ("diamond", 1, None),
    "diamond-open": ("diamond", 0, None),
    "er-one": ("ERone", 0, None),
    "er-mandatory-one": ("ERmandOne", 0, None),
    "er-many": ("ERmany", 0, None),
    "er-zero-one": ("ERzeroToOne", 0, None),
    "er-zero-many": ("ERzeroToMany", 0, None),
    "er-one-many": ("ERoneToMany", 0, None),
    "inherit": ("block", 0, 16),
    "realize": ("block", 0, 16),
    "aggregation": ("diamondThin", 0, 24),
    "composition": ("diamondThin", 1, 24),
    "dependency": ("open", 0, None),
}

# Keys the emitter may write (superset of what `style_raw` may use, see core/schema.py).
VERTEX_EMIT_KEYS = frozenset(S.VERTEX_STYLE_KEYS | {
    "html", "shape", "container", "collapsible", "startSize", "horizontal", "childLayout",
    "horizontalStack", "resizeParent", "resizeParentMax", "resizeLast", "marginBottom",
    "points", "portConstraint", "resizable", "connectable",
})
VERTEX_EMIT_BARE = frozenset(("swimlane", "text", "edgeLabel"))
EDGE_EMIT_KEYS = frozenset(S.EDGE_STYLE_KEYS | {
    "html", "edgeStyle", "exitX", "exitY", "exitDx", "exitDy", "entryX", "entryY", "entryDx",
    "entryDy", "orthogonalLoop",
})


def validate_pairs(pairs, kind):
    """Reject duplicate keys and keys outside the allowed list; `html` may only be 0."""
    keys = VERTEX_EMIT_KEYS if kind == "vertex" else EDGE_EMIT_KEYS
    bare = VERTEX_EMIT_BARE if kind == "vertex" else frozenset()
    seen = set()
    for key, value in pairs:
        if value is None:
            if key not in bare:
                raise ValueError("style token %r not allowed for %s" % (key, kind))
        elif key not in keys:
            raise ValueError("style key %r not allowed for %s" % (key, kind))
        if key in seen:
            raise ValueError("duplicate style key %r" % key)
        seen.add(key)
        if key == "html" and value != "0":
            raise ValueError("html must be 0")
    return pairs


def merge_raw(pairs, style_raw):
    """Append `style_raw` (already validated) AFTER the theme pairs; same key overrides in place."""
    if not style_raw:
        return list(pairs)
    out = list(pairs)
    index = {k: i for i, (k, _) in enumerate(out)}
    for seg in style_raw.split(";"):
        key, val = seg.split("=", 1)
        if key in index:
            out[index[key]] = (key, val)
        else:
            index[key] = len(out)
            out.append((key, val))
    return out


def to_string(pairs):
    return "".join((k + ";") if v is None else ("%s=%s;" % (k, v)) for k, v in pairs)


def _theme(name):
    return T.THEMES[name]


def _text_props(theme, font_style, font_size, align="center", vertical="middle"):
    return [
        ("fontColor", theme["text"]), ("fontFamily", T.FONT_FAMILY), ("fontSize", str(font_size)),
        ("fontStyle", str(font_style)), ("align", align), ("verticalAlign", vertical),
    ]


def vertex_style(theme_name, cell):
    theme = _theme(theme_name)
    spec = T.VERTEX_ROLE_STYLES[cell["role"]]
    pairs = []
    if spec["token"]:
        pairs.append((spec["token"], None))
    pairs += [("rounded", "0"), ("html", "0")]
    accent = theme["accent"] if spec.get("container") else None
    pairs.append(("fillColor", spec["fill"] if spec["fill"] else "none"))
    if spec["stroke"]:
        pairs.append(("strokeColor", accent or theme["stroke"]))
        pairs.append(("strokeWidth", "2" if accent else "1"))
    else:
        pairs.append(("strokeColor", "none"))
    pairs.append(("labelBackgroundColor", "none"))
    vertical = "top" if cell["role"] in ("container", "text", "title") else "middle"
    pairs += _text_props(theme, spec["font_style"], spec["font_size"], spec["align"], vertical)
    if spec["align"] == "left":
        pairs.append(("spacingLeft", "8" if cell["role"] == "container" else "4"))
    if spec.get("container"):
        pairs += [("container", "1"), ("collapsible", "0")]
    return pairs


def table_style(theme_name, cell):
    theme = _theme(theme_name)
    variant = cell["variant"] or "plain"
    gray, _ = T.TABLE_VARIANTS[variant]
    accent = theme["accent"] if variant == "new" else None
    pairs = [
        ("swimlane", None), ("childLayout", "stackLayout"), ("horizontal", "1"),
        ("startSize", str(S.TABLE_START_SIZE)), ("horizontalStack", "0"), ("resizeParent", "1"),
        ("resizeParentMax", "0"), ("resizeLast", "0"), ("collapsible", "0"), ("marginBottom", "0"),
        ("rounded", "0"), ("html", "0"), ("fillColor", gray), ("swimlaneFillColor", gray),
        ("strokeColor", accent or theme["stroke"]), ("strokeWidth", "2" if accent else "1"),
        ("labelBackgroundColor", "none"),
    ]
    pairs += _text_props(theme, 1, T.FONT_SIZE, "center", "middle")
    return pairs


def table_title(cell):
    _, prefix = T.TABLE_VARIANTS[cell["variant"] or "plain"]
    return prefix + cell["title"]


def row_style(theme_name, row):
    theme = _theme(theme_name)
    if row["role"] == "separator":
        return [("shape", "line"), ("html", "0"), ("strokeColor", theme["stroke"]), ("strokeWidth", "1"),
                ("fillColor", "none"), ("labelBackgroundColor", "none"), ("rotatable", "0"),
                ("points", "[[0,0.5],[1,0.5]]"), ("portConstraint", "eastwest")] + \
            _text_props(theme, 0, T.FONT_SIZE, "left", "top")
    pairs = [("text", None), ("html", "0"), ("strokeColor", "none"), ("fillColor", "none"),
             ("labelBackgroundColor", "none")]
    pairs += _text_props(theme, T.ROW_ROLE_FONT_STYLE[row["role"]], T.FONT_SIZE, "left", "top")
    pairs += [("spacingLeft", "4"), ("spacingRight", "4"), ("rotatable", "0"),
              ("points", "[[0,0.5],[1,0.5]]"), ("portConstraint", "eastwest")]
    return pairs


def line_pattern(edge):
    """Single source of truth for dashing: `line` > role default > solid."""
    name = edge["line"] or T.EDGE_ROLE_STYLES[edge["role"]][0]
    return name, T.LINE_PATTERNS[name]


def edge_style(theme_name, edge):
    theme = _theme(theme_name)
    start, end = ARROWS[edge["start"]], ARROWS[edge["end"]]
    width = edge["stroke_width"] if edge["stroke_width"] is not None else T.EDGE_ROLE_STYLES[edge["role"]][1]
    pairs = [("edgeStyle", "orthogonalEdgeStyle"), ("rounded", "0"), ("html", "0")]
    for prefix, port in (("exit", edge["exit"]), ("entry", edge["entry"])):
        if port is not None:
            pairs += [(prefix + "X", fmt_ratio(port["x"])), (prefix + "Y", fmt_ratio(port["y"])),
                      (prefix + "Dx", "0"), (prefix + "Dy", "0")]
    pairs += [("startArrow", start[0]), ("startFill", str(start[1]))]
    if start[2] is not None:
        pairs.append(("startSize", str(start[2])))
    pairs += [("endArrow", end[0]), ("endFill", str(end[1]))]
    if end[2] is not None:
        pairs.append(("endSize", str(end[2])))
    pairs += [("strokeColor", theme["edge"]), ("strokeWidth", fmt(width))]
    name, pattern = line_pattern(edge)
    if pattern is None:
        pairs.append(("dashed", "0"))
    else:
        pairs += [("dashed", "1"), ("dashPattern", pattern)]
    pairs += [("labelBackgroundColor", theme["page"]), ("fontColor", theme["text"]),
              ("fontFamily", T.FONT_FAMILY), ("fontSize", str(T.FONT_SIZE))]
    if edge.get("loop"):
        pairs.append(("orthogonalLoop", "1"))
    return pairs


def edge_label_style(theme_name):
    theme = _theme(theme_name)
    return [("edgeLabel", None), ("html", "0"), ("resizable", "0"), ("connectable", "0"),
            ("fillColor", "none"), ("strokeColor", "none"), ("labelBackgroundColor", theme["page"])] + \
        _text_props(theme, 0, T.FONT_SIZE, "center", "middle")


def check_theme_name(name):
    if name not in T.THEMES:
        raise ValidationError("unknown theme '%s'" % name, "theme")
    return name
