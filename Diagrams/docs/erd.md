# kind `erd` (erd-meta-v1): meta.json -> ERD draw.io, layout automatic

You write the project's `*.meta.json` (the format of `erd_mau_02.meta.json`); the tool places the tables
and routes the lines. Output is the same native, editable draw.io XML as kind `raw`
(see raw.md and themes.md). The kind is recognised by structure: no `kind` key, `schema_version`
the STRING "1", arrays `tables` and `relationships`.

## Usage

    python -B -m diagram_tool erd_mau_02.meta.json                  # -> erd_mau_02.gen.drawio (next to the input)
    python -B -m diagram_tool erd_mau_02.meta.json -o D:\out        # existing directory: default name inside it
    python -B -m diagram_tool erd_mau_02.meta.json --kind erd --no-clobber
    Diagrams\Gen-Erd.ps1                                            # paste the path of a *.meta.json (loops); also in menu_scripts.ps1
    Diagrams\lib\Convert-ToDrawio.ps1 <file|folder> -Kind erd       # the shared engine (options: -OutputPath, -Theme, -NoClobber)

- Default output drops `.meta` and adds `.gen.drawio`, so a hand-drawn `erd_mau_02.drawio` is not the default target.
- `--kind erd` makes any other kind of file an error (exit 1). `--no-clobber` keeps an existing output
  (`skipped: <path>`); a written file prints `wrote: <path>` on stderr.
- Exit codes and ASCII messages as in raw.md. `warning:` lines (stderr) report a `foreign_keys` column that has no
  entry in `relationships` (the column is still marked FK, no edge is drawn).

## What is read

`mau.ten_mau`, `version` (title block), `tables[]`, `relationships[]`.

- Table: `name` (a valid id: no whitespace or ':'), `kind` NEW|EXTEND|REUSE, `columns[]` (`name`, `pg_type`, `nullable`, `change`),
  `primary_key[]` (default `["id"]`), `foreign_keys[].columns`, `uniques[]`, `indexes[]`, `checks[]`, `other_columns`.
- Relationship: `parent`, `child`, `fk_column`, `parent_card` and `child_card` in {"1", "0..1", "0..N", "1..N"}, `label`.
  Unknown parent/child, bad cardinality, empty `fk_column` or duplicate table names are errors with a field path.

## Table body (what is shown)

| kind | rows |
|------|------|
| NEW | primary key + every column |
| EXTEND | primary key + FK columns + columns with `change` (label ends with ` (ADD)` etc.); `... cac cot khac khong doi` if `other_columns` |
| REUSE | primary key + FK columns derived from relationships |

Row label `<column> <type>`; ` NULL` if nullable; ` PK` on key columns (` FK` too if also a foreign key); FK columns are
italic, PK bold. Audit columns are not in the meta and not drawn. Then one `note` row per unique (`UK name(cols)`), index
(`IX name(cols)`) and check (`CK name: expr`), each cut at 56 characters with `...`. Titles carry `[NEW]`/`[EXTEND]`/`[REUSE]`
and the gray level of the theme. Every table cell has `entity` and `kind` attributes (it is wrapped in `<object>`, like
the hand-drawn diagrams). Table width is estimated from the text (Arial 12 approximation, 200..440 px) and widened (up to
800 px) when many lines meet one face: a face holds `capacity` ports 20 px apart and keeps spare room; more than 38 lines on
one face is an error.

A title block (`mau.ten_mau` + `version`) and a legend note (`[NEW]` white, `[EXTEND]` light gray, `[REUSE]` dark gray)
sit above the diagram. `-o` ending in `/` or `\` must name an existing directory (otherwise exit 2).

## Lines

One edge per relationship, source = parent, target = child, id `rel.<child>.<fk_column>` (`_2`... on repeats). Ends follow
the cardinality: "1" mandatory-one, "0..1" zero-or-one, "0..N" zero-or-many, "1..N" one-or-many; the label is `label`
(placed on the line, may overlap neighbours; no label avoidance). Parents are drawn above children; in a cycle the lighter
relationship (weight: parent "1" = 8, child "0..1" = 1, else 4) is the one drawn upwards, so for `co_so` <-> `khu_tap_trung`
the cardinality-heavier side wins. A reversed line still leaves the parent and enters the child; only its route goes upwards.
A self-referencing relationship (max 3 per table) loops on the right side of the table.

## Layout (summary)

Weighted cycle removal, network-simplex layering, dummy nodes for long lines, median + transpose ordering, x by weighted
isotonic regression per layer, ports on a fixed 1/40 grid of each table face, tracks (horizontal lanes) between layers,
orthogonal routes with 24 px minimum first/last stubs. Guarantees checked by the tests (without opening draw.io): no two
tables overlap, no two lines share a stretch of the same line, no line crosses a table, every line passes the `raw` validator
and equals the polyline of draw.io's `SegmentConnector` (ported from the source, 32.6.9). Crossings, bends and size on the
real `erd_mau_02` data are frozen as regression bounds. Not done in v1: moving tables by hints (`*.diagram.json`), label
collision avoidance, hiding columns.

UNVERIFIED (never opened in draw.io): real rendering of the ER markers and `shape=line` separators, straight lines without
`points` (not ported), the width estimate against real fonts.
