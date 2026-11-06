"""Constants of the `raw` schema (vocabularies, limits, allowed style keys).

The emitter (emit/styles.py, Step 3) maps arrow symbols and roles to draw.io style
strings; this module only names the vocabulary so the validator can check it.
"""

import re

SCHEMA_VERSION = 1
THEMES = ("mono", "accent")

VERTEX_ROLES = ("box", "container", "text", "note", "title")
TABLE_ROLES = ("table",)
ROW_ROLES = ("pk", "fk", "plain", "note", "separator")
EDGE_ROLES = ("line", "dependency", "return")
LINE_STYLES = ("solid", "dashed", "dotted")
# `variant` values per cell type (themes map them to grays / title prefixes).
VERTEX_VARIANTS = ("plain",)
TABLE_VARIANTS = ("plain", "new", "extend", "reuse")
EDGE_VARIANTS = ("plain",)

# Names accepted for `start` / `end` of an edge (mapping to markers lives in emit/styles.py).
ARROW_SYMBOLS = (
    "none", "classic", "open", "block", "block-open", "diamond", "diamond-open",
    "er-one", "er-mandatory-one", "er-many", "er-zero-one", "er-zero-many", "er-one-many",
    "inherit", "realize", "aggregation", "composition", "dependency",
)
DEFAULT_START = "none"
DEFAULT_END = "classic"

# Table geometry constants (the same for every theme; the emitter and the stackLayout
# simulation use these values).
TABLE_START_SIZE = 30
TABLE_ROW_H = 26

COORD_LIMIT = 1000000
MIN_SEGMENT = 2          # draw.io drops control points closer than 1 px; we demand >= 2
ALIGN_EPS = 1e-6
PAGE_MARGIN = 40
DEFAULT_PAGE_W = 850
DEFAULT_PAGE_H = 1100

# `\Z` (not `$`): Python's `$` also matches before a trailing newline.
VARIANT_RE = re.compile(r"^[a-z][a-z0-9_-]{0,31}\Z")
TAG_RE = re.compile(r"^[A-Za-z0-9_.-]{1,64}\Z")
ATTR_KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_.-]{0,63}\Z")
STYLE_KEY_RE = re.compile(r"^[A-Za-z][A-Za-z0-9]*\Z")
PORT_DECIMALS = 4        # exitX/entryX... are emitted with up to 4 decimals (not via fmt)
GRID_DECIMALS = 1        # coordinates are written with fmt() = 1 decimal, so inputs must fit
RESERVED_ATTR_KEYS = ("id", "label", "placeholders", "placeholder", "tooltip", "link")

# Keys allowed in `style_raw`, split by cell kind. `html` is never allowed. Keys that would
# override geometry the validator has checked (ports, router, shape/perimeter, swimlane
# header and stack layout) are deliberately NOT allowed: use the JSON fields instead.
# `startSize` is allowed on edges only (marker size there; header height on vertices).
VERTEX_STYLE_KEYS = frozenset((
    "rounded", "whiteSpace", "fillColor", "strokeColor", "fontColor", "fontSize",
    "fontStyle", "fontFamily", "align", "verticalAlign", "spacing", "spacingLeft",
    "spacingRight", "spacingTop", "spacingBottom", "dashed", "dashPattern", "strokeWidth",
    "labelBackgroundColor", "swimlaneFillColor", "rotatable", "opacity", "fillOpacity",
    "strokeOpacity", "arcSize", "glass", "shadow", "textOpacity",
))
VERTEX_STYLE_BARE = frozenset()
EDGE_STYLE_KEYS = frozenset((
    "rounded", "endArrow", "startArrow", "endFill", "startFill", "endSize", "startSize",
    "strokeColor", "strokeWidth", "fontColor", "fontSize", "fontFamily", "fontStyle",
    "labelBackgroundColor", "dashed", "dashPattern", "jumpStyle", "jumpSize", "opacity",
))
EDGE_STYLE_BARE = frozenset()
