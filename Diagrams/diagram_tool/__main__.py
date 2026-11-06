"""CLI: python -B -m diagram_tool <input.json> [-o out.drawio] [--stdout] [--theme mono|accent]

Exit codes: 0 ok; 1 the JSON is malformed or invalid (message on stderr); 2 usage or I/O error.
All messages are ASCII. Output is UTF-8, LF line endings, no BOM.
"""

import argparse
import os
import sys
import tempfile

from .core import jsonio
from .core.errors import DiagramError, InputError, ValidationError, ascii_safe
from .core.schema import THEMES
from .kinds.raw import to_drawio

KINDS = {"raw": to_drawio}


def build_parser():
    p = argparse.ArgumentParser(prog="diagram_tool", description="Convert a diagram JSON file to draw.io (.drawio).")
    p.add_argument("input", help="input JSON file")
    p.add_argument("-o", "--output", help="output file (default: <input> with .drawio extension)")
    p.add_argument("--stdout", action="store_true", help="write the XML to standard output instead of a file")
    p.add_argument("--theme", choices=THEMES, help="override the theme of the document")
    return p


def convert(data, theme=None):
    kind = data.get("kind") if isinstance(data, dict) else None
    if isinstance(data, dict) and "kind" not in data:
        raise ValidationError("missing required key 'kind'")
    if kind not in KINDS:
        raise ValidationError("unsupported kind (supported: %s)" % ", ".join(sorted(KINDS)), "kind")
    return KINDS[kind](data, theme)


def write_atomic(path, text):
    """Write `text` (UTF-8, LF, no BOM) to `path` via a temp file in the same directory + replace."""
    directory = os.path.dirname(os.path.abspath(path))
    tmp = None
    try:
        fd, tmp = tempfile.mkstemp(prefix=".diagram_tool_", suffix=".tmp", dir=directory)
        with os.fdopen(fd, "wb") as handle:
            handle.write(text.encode("utf-8"))
        os.replace(tmp, path)
        tmp = None
    except OSError as exc:
        raise InputError("cannot write %s: %s" % (path, exc.strerror or exc))
    finally:
        if tmp is not None:
            try:
                os.unlink(tmp)
            except OSError:
                pass


def _same_file(a, b):
    try:
        if os.path.exists(a) and os.path.exists(b):
            return os.path.samefile(a, b)
    except OSError:
        pass
    return os.path.normcase(os.path.abspath(a)) == os.path.normcase(os.path.abspath(b))


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)  # argparse exits with code 2 on usage errors
    if args.stdout and args.output:
        sys.stderr.write("error: use either --stdout or -o, not both\n")
        return 2
    try:
        data = jsonio.load_file(args.input)
        xml, warnings = convert(data, args.theme)
        for message in warnings:
            sys.stderr.write("warning: %s\n" % ascii_safe(message))
        if args.stdout:
            sys.stdout.buffer.write(xml.encode("utf-8"))
            sys.stdout.buffer.flush()
        else:
            out = args.output or os.path.splitext(args.input)[0] + ".drawio"
            if _same_file(out, args.input):
                raise InputError("output would overwrite the input file: %s" % out)
            write_atomic(out, xml)
    except DiagramError as exc:
        sys.stderr.write("error: %s\n" % exc)
        return exc.exit_code
    return 0


if __name__ == "__main__":
    sys.exit(main())
