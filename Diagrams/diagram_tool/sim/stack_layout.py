"""Port of draw.io's mxStackLayout.execute() (mxgraph 32.6.9, mxStackLayout.js:370-597,
631-679) as a pure function (the Graph.js layout manager, Graph.js:12635-12656, sets fill=true).

Used ONLY in tests: a table we emit must be a FIXED POINT of this layout, otherwise draw.io
would move/resize its rows the first time the table is edited.

Scope: swimlane parent with the title at the top (`horizontal=1`, startSize = header height),
all children movable, no wrap, no allowGaps/snap, no footer.

Stroke width: mxStackLayout.borderCollapse is true (mxStackLayout.js:155) and nothing in
Graph.js changes it, so child stroke widths are ignored (`sw = 0`, lines 445 and 486). The
`border_collapse=False` option exists only to document what would happen otherwise.

NOTE: the function defaults are NOT draw.io's Graph.js defaults (horizontalStack and
resizeParentMax default to '1' there). The emitter writes `horizontalStack=0;resizeParentMax=0;
resizeParent=1;resizeLast=0` explicitly, and tests call this function with matching arguments.
"""

import math


def _floor_half(stroke_width):
    return math.floor(stroke_width / 2)


def stack_layout(parent_w, parent_h, children, start_size=0, horizontal=False, spacing=0,
                 border=0, margin_left=0, margin_right=0, margin_top=0, margin_bottom=0,
                 fill=True, resize_parent=True, resize_parent_max=False, resize_last=False,
                 keep_first_location=False, border_collapse=True):
    """Run the layout.

    children: list of dicts {x, y, w, h, stroke_width (default 1)} in stack order.
    Returns (children_out, parent_w, parent_h); children_out are dicts with x, y, w, h.
    """
    fill_value = (parent_h - margin_top - margin_bottom) if horizontal \
        else (parent_w - margin_left - margin_right)
    fill_value -= 2 * border
    x0 = 0 + border + margin_left
    y0 = 0 + border + margin_top

    # getActualStartSize for a north-title swimlane: only startSize.y is set; it is clamped to
    # the parent height. Width/height strips and footers are 0.
    start_y = min(start_size, parent_h)
    if horizontal:
        fill_value -= start_y
    y0 += start_y

    out = []
    last = None
    last_value = 0
    last_index = None
    for child in children:
        geo = {"x": child["x"], "y": child["y"], "w": child["w"], "h": child["h"]}
        sw = 0 if border_collapse else child.get("stroke_width", 1)
        if last is not None:
            temp = last_value + spacing + _floor_half(sw)
            if horizontal:
                geo["x"] = temp - margin_left + margin_left
            else:
                geo["y"] = temp - margin_top + margin_top
        elif not keep_first_location:
            if horizontal:
                geo["x"] = x0
            else:
                geo["y"] = y0

        if horizontal:
            geo["y"] = y0
        else:
            geo["x"] = x0

        if fill and fill_value is not None:
            if horizontal:
                geo["h"] = fill_value
            else:
                geo["w"] = fill_value

        out.append(geo)
        last = geo
        last_index = len(out) - 1
        if horizontal:
            last_value = last["x"] + last["w"] + _floor_half(sw)
        else:
            last_value = last["y"] + last["h"] + _floor_half(sw)

    new_w, new_h = parent_w, parent_h
    if resize_parent and last is not None:
        if horizontal:
            tmp = last["x"] + last["w"] + margin_right + border
            new_w = max(parent_w, tmp) if resize_parent_max else tmp
        else:
            tmp = last["y"] + last["h"] + margin_bottom + border
            new_h = max(parent_h, tmp) if resize_parent_max else tmp
    elif resize_last and last is not None and last_index is not None:
        if horizontal:
            last["w"] = parent_w - last["x"] - spacing - margin_right
        else:
            last["h"] = parent_h - last["y"] - spacing - margin_bottom
    return out, new_w, new_h
