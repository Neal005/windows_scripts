"""Shared geometry helpers on normalised `raw` cells (dicts with x, y, w, h, parent)."""


def origin(by_id, cell_id):
    """Absolute top-left corner of a vertex/table; (0, 0) for None (the page)."""
    x = 0
    y = 0
    cur = cell_id
    while cur is not None:
        cell = by_id[cur]
        x += cell["x"]
        y += cell["y"]
        cur = cell["parent"]
    return (x, y)


def port_point(by_id, cell_id, port):
    """Absolute coordinates of a port {x, y} (fractions of w/h) on a vertex/table."""
    cell = by_id[cell_id]
    ox, oy = origin(by_id, cell_id)
    return (ox + port["x"] * cell["w"], oy + port["y"] * cell["h"])


def edge_endpoints(by_id, edge):
    """(exit_point, entry_point) of a normalised edge in the coordinate frame of its parent.

    Requires edge["exit"] and edge["entry"]. This is the frame in which `points` are written.
    """
    px, py = origin(by_id, edge["parent"])
    ex, ey = port_point(by_id, edge["source"], edge["exit"])
    nx, ny = port_point(by_id, edge["target"], edge["entry"])
    return (ex - px, ey - py), (nx - px, ny - py)


def table_row_geometry(table, start_size):
    """Geometry (x, y, w, h) of each row of a normalised table, relative to the table.

    stackLayout invariant: x = 0, width = table width, y accumulates from `start_size`.
    """
    out = []
    y = start_size
    for row in table["rows"]:
        out.append((0, y, table["w"], row["h"]))
        y += row["h"]
    return out
