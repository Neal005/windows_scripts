# kind `raw`: JSON -> draw.io

Hand-placed blocks, tables and orthogonal edges. Every coordinate is written by you; the tool
validates it, picks styles from a theme and writes native, editable draw.io XML (every block is
a vertex, every line an edge with real `source`/`target`, containers have children, tables are
swimlanes with rows). Layout algorithms for other kinds (ERD, sequence, ...) come later.

## Usage

    python -B -m diagram_tool <input.json> [-o out.drawio] [--stdout] [--theme mono|accent]

- Default output: the input path with `.drawio`. `-o` and `--stdout` are exclusive.
- Exit codes: 0 ok, 1 invalid JSON/schema (message `error: <path>: <reason>` on stderr, ASCII),
  2 usage or I/O error. Warnings (`warning: ...`) go to stderr and do not change the exit code.
- Output: UTF-8, LF, no BOM, written atomically (temp file + replace). Same input -> same bytes.
- An existing output file is overwritten. Hand-edit protection (`.bak`, `--check`) is planned for G0a2;
  until then never point `-o` at a hand-drawn diagram.

## File

    {"schema_version": 1, "kind": "raw", "title": "...", "theme": "mono",
     "meta": {"owner": "..."}, "pages": [ ... ]}

- `meta`: extra attributes written on cell "0" (names: `[A-Za-z_][A-Za-z0-9_.-]*`, not `id`, `label`,
  `placeholders`, `placeholder`, `tooltip`, `link`, not starting with `xml`; `generator` and `title` are
  written by the tool and rejected here). `title` defaults to the first page name.
- Unknown keys are errors (typos fail loudly). JSON must not contain duplicate keys, NaN/Infinity or
  booleans where a number is expected.

## Page

`{"id": "p1", "name": "Trang 1", "width": 1600, "height": 1000, "cells": [...]}`

`width`/`height` are optional: when missing they are derived from the bounding box of all blocks and edge
points plus a 40 px margin, rounded up to 10. Cell order is meaningful (stacking order); key order is not.
Cell ids appear in the XML as `<pageId>:<id>`, table rows as `<pageId>:<tableId>:<rowId>`, extra edge labels
as `<pageId>:<edgeId>:<labelId>`. Ids: 1..200 characters, no whitespace, no `:`.

## Cells

Common keys: `id`, `type`, `role`, `variant`, `tags`, `attrs`, `style_raw`.
`attrs` (string values) wrap the cell in `<object>` (the label becomes the object's `label`).

### vertex
`x y w h` required (`w`,`h` > 0), `label` optional (`\n` = line break), `parent` optional.
Roles: `box` (default), `container`, `text`, `note`, `title`. `variant`: `plain`.
`parent` must be a `container`; child coordinates are relative to the parent and must lie inside it.
Top-level blocks need `x >= 0`, `y >= 0`.

### table
`x y w title rows` (`h` is computed: header 30 + sum of row heights; giving `h` is an error).
`variant`: `plain` (default), `new`, `extend`, `reuse` (grays + title prefix, see themes.md).
Rows: strings (label only) or `{"id", "label", "role", "h"}`; roles `plain` (default), `pk`, `fk`, `note`,
`separator` (label may be empty); row height 26 unless `h`. A missing row `id` is derived from the label
(Vietnamese diacritics stripped, slug, `_2`, `_3` on collisions): pass explicit ids when the table may be edited,
inserting a row with an equal label renumbers derived ids. Edges attach to the table block, never to a row.

### edge
`source`, `target` (vertex/table ids), optional `parent`, `role` (`line` default, `dependency`, `return`),
`line` (`solid|dashed|dotted`), `stroke_width`, `start`/`end` (default `none`/`classic`), `exit`/`entry`,
`points`, `label` or `labels`.

- Symbols for `start`/`end`: none, classic, open, block, block-open, diamond, diamond-open, er-one,
  er-mandatory-one, er-many, er-zero-one, er-zero-many, er-one-many, inherit, realize, aggregation,
  composition, dependency. A symbol only chooses the marker; dashing never follows from it.
- Dashing: `line` wins, else the role (`dependency` dashed, `return` dotted), else solid.
- `labels`: `[{"id", "text", "pos" (-1..1), "dx", "dy"}]`; `label` is shorthand for one label at `pos` 0.
  The first label is the edge's own text (double-click edits it); later ones are child cells and need an `id`.
- `parent`: default is the lowest container that contains both ends (the page if none). If given it must be
  a container that is an ancestor of both ends. A self-connecting edge on a block lives in the block's container;
  a self-connecting edge on a container cannot name that container itself as `parent` (it lives in the
  container's parent). `points` are in the coordinate system of that parent.

### Ports and corner points

`exit`/`entry` = `{"x": 0..1, "y": 0..1}` on the block outline: exactly one of x, y is 0 or 1 (a corner is
ambiguous and rejected). Port fractions may have up to 4 decimals; every other number up to 1 decimal
(so what is checked is what is written). `points` are the corners of the polyline, absolute within the parent:

- `exit` and `entry` are required whenever `points` is given;
- the first point lies on the exit port's axis (same y for a left/right port, same x for top/bottom), the last
  on the entry port's axis;
- consecutive points share x or y (no diagonals);
- every segment, including the first and last, is at least 2 px;
- every point is a real bend: neighbouring segments alternate horizontal/vertical (a collinear point or a
  U-turn is rejected, draw.io would silently drop or reroute it);
- a self-connecting edge needs at least 2 points and is written with `orthogonalLoop=1`.

An edge without `points` is a straight/auto-routed connector. A port such as 0.3333 cannot be matched by any
corner on a 1-decimal grid, so choose ports that give 1-decimal positions (0.5, 0.25, 0.1 ...).

### style_raw
A `;`-separated list of `key=value` appended after the theme style (same key replaces it). Only visual keys are
allowed (colours, fonts, `strokeWidth`, `dashed`, `dashPattern`, `rounded`, opacity ...; edges also marker
keys). Anything that would change geometry or routing (`exitX`, `edgeStyle`, `startSize` on blocks, stack layout
keys, `shape`, `html`, ...) is rejected. Using it prints a warning and may break theme invariants (for example a
non-gray colour in `mono`).

## What is checked, and what is not

Checked by tests (no draw.io needed): XML structure and references, escaping, determinism, theme rules, tables
are fixed points of a port of `mxStackLayout` (draw.io 32.6.9), corner lists equal the polyline of a port of
`mxEdgeStyle.SegmentConnector`.

UNVERIFIED (never opened in draw.io): real rendering of markers and `shape=line` separators, `<object>` surviving
a save/open round trip, `adaptiveColors="none"` in dark mode, edges without `points` (OrthConnector is not
ported), perimeter projection on rounded shapes, forward references (an edge listed before its container).
Edges carry no `fillColor` (it has no effect on a connector).
