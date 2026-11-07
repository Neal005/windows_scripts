#!/usr/bin/env python
"""
pdf_dump.py - READ-ONLY dump of a .pdf for the Claude QA reviewer.
Needs pdfplumber (installed in the helpers venv). Never writes anything.

Usage (through the qa-read wrapper):
  qa-read pdf <file.pdf> info
      Page count, metadata, and whether pages have a text layer.
  qa-read pdf <file.pdf> text [--pages 1-3] [--max-chars N]
      Extracted text per page. Default: first 5 pages.
  qa-read pdf <file.pdf> tables <page>
      Tables detected on one page, row by row.
  qa-read pdf <file.pdf> grep <pattern>
      Case-insensitive search over all pages, with page number.
"""
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

try:
    import pdfplumber
except ImportError:
    sys.exit("pdfplumber is not installed in the helpers venv")


def parse_pages(spec, total):
    pages = set()
    for part in spec.split(","):
        if "-" in part:
            a, b = part.split("-", 1)
            pages.update(range(int(a), int(b) + 1))
        else:
            pages.add(int(part))
    return [p for p in sorted(pages) if 1 <= p <= total]


def opt(args, name, default):
    if name in args:
        return args[args.index(name) + 1]
    return default


def cmd_info(pdf):
    print("Pages: %d" % len(pdf.pages))
    for k, v in (pdf.metadata or {}).items():
        print("Meta %s: %s" % (k, str(v)[:200]))
    empty = [i for i, p in enumerate(pdf.pages, 1) if not (p.extract_text() or "").strip()]
    if empty:
        shown = ", ".join(map(str, empty[:30]))
        print("Pages WITHOUT text layer (likely scanned, cannot read): %s%s"
              % (shown, " ..." if len(empty) > 30 else ""))
    else:
        print("All pages have a text layer.")


def cmd_text(pdf, args):
    total = len(pdf.pages)
    pages = parse_pages(opt(args, "--pages", "1-5"), total)
    max_chars = int(opt(args, "--max-chars", "20000"))
    used = 0
    for n in pages:
        txt = (pdf.pages[n - 1].extract_text() or "").strip()
        print("===== Page %d/%d =====" % (n, total))
        print(txt if txt else "[no text layer]")
        used += len(txt)
        if used >= max_chars:
            print("... stopped at --max-chars %d" % max_chars)
            break


def cmd_tables(pdf, page_no):
    if not 1 <= page_no <= len(pdf.pages):
        sys.exit("Page %d not found (document has %d pages)" % (page_no, len(pdf.pages)))
    tables = pdf.pages[page_no - 1].extract_tables()
    print("Page %d: %d table(s)" % (page_no, len(tables)))
    for t_i, table in enumerate(tables, 1):
        print("\n--- Table %d ---" % t_i)
        for r_i, row in enumerate(table, 1):
            cells = [(c or "").replace("\n", " ").strip() for c in row]
            print("R%d: %s" % (r_i, " | ".join(cells)))


def cmd_grep(pdf, pattern):
    rx = re.compile(re.escape(pattern), re.IGNORECASE)
    hits = 0
    for n, page in enumerate(pdf.pages, 1):
        for line in (page.extract_text() or "").splitlines():
            if rx.search(line):
                print("p%d: %s" % (n, line.strip()[:300]))
                hits += 1
    print("Total matches: %d" % hits)


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    path, mode, rest = argv[1], argv[2], argv[3:]
    with pdfplumber.open(path) as pdf:
        if mode == "info":
            cmd_info(pdf)
        elif mode == "text":
            cmd_text(pdf, rest)
        elif mode == "tables" and rest:
            cmd_tables(pdf, int(rest[0]))
        elif mode == "grep" and rest:
            cmd_grep(pdf, rest[0])
        else:
            sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
