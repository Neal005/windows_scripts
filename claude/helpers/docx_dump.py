#!/usr/bin/env python
"""
docx_dump.py - READ-ONLY dump of a .docx for the Claude QA reviewer.

Standard library only (zipfile + xml), no python-docx needed, never writes
anything. Word splits text into many runs; this joins them per paragraph so
template tags and cell text come out whole.

Usage:
  qa-read docx <file.docx> summary
      List every table: index, heading above it, rows x cols, header row.
  qa-read docx <file.docx> table <N> [--max-rows R]
      Print table N (1-based) row by row. Default max 300 rows.
  qa-read docx <file.docx> text [--max-lines L]
      Print body paragraphs outside tables, with their order index.
  qa-read docx <file.docx> tags
      List template tags ({{ }}, {% %}, ${ }, << >>) and where they occur.
  qa-read docx <file.docx> grep <pattern>
      Case-insensitive search in paragraphs and table cells, with location.
"""
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
TAG_RE = re.compile(r"\{\{.*?\}\}|\{%.*?%\}|\$\{.*?\}|\u00ab.*?\u00bb")

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


def load_body(path):
    with zipfile.ZipFile(path, "r") as z:
        root = ET.fromstring(z.read("word/document.xml"))
    return root.find(W + "body")


def walk(elem):
    """Yield body-level w:p and w:tbl in document order (descends into w:sdt)."""
    for child in elem:
        if child.tag in (W + "p", W + "tbl"):
            yield child
        elif child.tag == W + "sdt":
            content = child.find(W + "sdtContent")
            if content is not None:
                yield from walk(content)


def para_text(p):
    return "".join(t.text or "" for t in p.iter(W + "t")).strip()


def cell_text(tc):
    parts = [para_text(p) for p in tc.iter(W + "p")]
    return " / ".join(x for x in parts if x)


def cell_marker(tc):
    pr = tc.find(W + "tcPr")
    marks = []
    if pr is not None:
        span = pr.find(W + "gridSpan")
        if span is not None and span.get(W + "val", "1") != "1":
            marks.append("span=" + span.get(W + "val"))
        vm = pr.find(W + "vMerge")
        if vm is not None and vm.get(W + "val") != "restart":
            marks.append("merged-above")
    return ("[" + ",".join(marks) + "] ") if marks else ""


def rows_of(tbl):
    return tbl.findall(W + "tr")


def row_cells(tr):
    return [cell_marker(tc) + cell_text(tc) for tc in tr.findall(W + "tc")]


def collect(body):
    """Return (tables, paragraphs). tables: list of (heading, tbl)."""
    tables, paras = [], []
    last_heading = ""
    for idx, el in enumerate(walk(body)):
        if el.tag == W + "p":
            txt = para_text(el)
            if txt:
                paras.append((idx, txt))
                last_heading = txt
        else:
            tables.append((last_heading, el))
    return tables, paras


def cmd_summary(tables):
    print("Total tables: %d" % len(tables))
    for i, (heading, tbl) in enumerate(tables, 1):
        rows = rows_of(tbl)
        ncols = max((len(r.findall(W + "tc")) for r in rows), default=0)
        header = " | ".join(row_cells(rows[0])) if rows else ""
        print("\n#%d  rows=%d cols=%d" % (i, len(rows), ncols))
        print("  heading: %s" % heading[:200])
        print("  header : %s" % header[:400])


def cmd_table(tables, n, max_rows):
    if not 1 <= n <= len(tables):
        sys.exit("Table %d not found (document has %d tables)" % (n, len(tables)))
    heading, tbl = tables[n - 1]
    rows = rows_of(tbl)
    print("Table #%d  heading: %s" % (n, heading))
    for r_i, tr in enumerate(rows[:max_rows], 1):
        print("R%d: %s" % (r_i, " | ".join(row_cells(tr))))
    if len(rows) > max_rows:
        print("... %d more rows not shown (use --max-rows)" % (len(rows) - max_rows))


def cmd_text(paras, max_lines):
    for idx, txt in paras[:max_lines]:
        print("P%d: %s" % (idx, txt))
    if len(paras) > max_lines:
        print("... %d more paragraphs not shown" % (len(paras) - max_lines))


def iter_locations(tables, paras):
    for idx, txt in paras:
        yield "P%d" % idx, txt
    for t_i, (_, tbl) in enumerate(tables, 1):
        for r_i, tr in enumerate(rows_of(tbl), 1):
            for c_i, txt in enumerate(row_cells(tr), 1):
                yield "T%d.R%d.C%d" % (t_i, r_i, c_i), txt


def cmd_tags(tables, paras):
    found = 0
    for loc, txt in iter_locations(tables, paras):
        for tag in TAG_RE.findall(txt):
            print("%s: %s" % (loc, tag))
            found += 1
    print("Total tags: %d" % found)


def cmd_grep(tables, paras, pattern):
    rx = re.compile(re.escape(pattern), re.IGNORECASE)
    hits = 0
    for loc, txt in iter_locations(tables, paras):
        if rx.search(txt):
            print("%s: %s" % (loc, txt[:300]))
            hits += 1
    print("Total matches: %d" % hits)


def opt(args, name, default):
    if name in args:
        i = args.index(name)
        return int(args[i + 1])
    return default


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    path, mode, rest = argv[1], argv[2], argv[3:]
    tables, paras = collect(load_body(path))
    if mode == "summary":
        cmd_summary(tables)
    elif mode == "table" and rest:
        cmd_table(tables, int(rest[0]), opt(rest, "--max-rows", 300))
    elif mode == "text":
        cmd_text(paras, opt(rest, "--max-lines", 500))
    elif mode == "tags":
        cmd_tags(tables, paras)
    elif mode == "grep" and rest:
        cmd_grep(tables, paras, rest[0])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
