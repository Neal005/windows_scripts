"""Themes: colours and per-role/variant presentation. No colour lives in the JSON.

mono (default): black text, #404040 outlines, white page, black connectors, three
meaningful grays #FFFFFF / #E0E0E0 / #BDBDBD (#F2F2F2 is decoration only).
accent: as mono plus exactly ONE colour (#1F4E79); every element that uses it also gets
strokeWidth=2 so its meaning does not depend on colour.
"""

FONT_FAMILY = "Arial"
FONT_SIZE = 12
TITLE_FONT_SIZE = 16
LINE_PATTERNS = {"solid": None, "dashed": "6 4", "dotted": "2 4"}

GRAY_WHITE = "#FFFFFF"
GRAY_LIGHT = "#E0E0E0"
GRAY_MID = "#BDBDBD"
GRAY_DECOR = "#F2F2F2"
ACCENT_COLOR = "#1F4E79"

THEMES = {
    "mono": {"text": "#000000", "stroke": "#404040", "page": "#FFFFFF", "edge": "#000000", "accent": None},
    "accent": {"text": "#000000", "stroke": "#404040", "page": "#FFFFFF", "edge": "#000000",
               "accent": ACCENT_COLOR},
}

# Table variant -> (header and body gray, title prefix). The prefix is the primary non-colour channel.
TABLE_VARIANTS = {
    "plain": (GRAY_WHITE, ""),
    "new": (GRAY_WHITE, "[NEW] "),
    "extend": (GRAY_LIGHT, "[EXTEND] "),
    "reuse": (GRAY_MID, "[REUSE] "),
}

# Vertex role -> presentation. `token` is a bare leading style token (acts as the shape).
VERTEX_ROLE_STYLES = {
    "box": {"token": None, "fill": GRAY_WHITE, "stroke": True, "font_style": 0, "font_size": FONT_SIZE, "align": "center"},
    "container": {"token": None, "fill": GRAY_DECOR, "stroke": True, "font_style": 1, "font_size": FONT_SIZE,
                  "align": "left", "container": True},
    "text": {"token": "text", "fill": None, "stroke": False, "font_style": 0, "font_size": FONT_SIZE, "align": "left"},
    "note": {"token": None, "fill": GRAY_LIGHT, "stroke": True, "font_style": 2, "font_size": FONT_SIZE, "align": "left"},
    "title": {"token": "text", "fill": None, "stroke": False, "font_style": 1, "font_size": TITLE_FONT_SIZE, "align": "left"},
}

ROW_ROLE_FONT_STYLE = {"pk": 1, "fk": 2, "plain": 0, "note": 4, "separator": 0}

# Edge role -> (line pattern name, stroke width)
EDGE_ROLE_STYLES = {
    "line": ("solid", 1),
    "dependency": ("dashed", 1),
    "return": ("dotted", 1),
}
