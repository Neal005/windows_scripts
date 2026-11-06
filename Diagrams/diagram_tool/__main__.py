"""CLI: python -B -m diagram_tool <input.json> [-o out.drawio|dir] [--stdout] [--theme mono|accent]
                               [--kind raw|erd] [--no-clobber]

Input kinds: `raw` (JSON with "kind": "raw": hand placed blocks/tables/edges) and `erd`
(erd-meta-v1: the project's *.meta.json, recognised by its structure; layout is automatic).
Default output: <input>.drawio for raw; for erd the `.meta` suffix is dropped and `.gen.drawio`
is used (erd_mau_02.meta.json -> erd_mau_02.gen.drawio), so a hand-drawn erd_mau_02.drawio is
never the default target. `-o` may be an EXISTING directory (default file name inside it).

Exit codes: 0 ok; 1 the JSON is malformed or invalid (message on stderr); 2 usage or I/O error.
Messages are ASCII; stderr also gets `wrote: <path>` or `skipped: <path>` (--no-clobber).
Output is UTF-8, LF line endings, no BOM.
"""

import argparse
import os
import sys
import tempfile

from .adapters.erd_meta_v1 import is_erd_meta
from .core import jsonio
from .core.errors import DiagramError, InputError, ValidationError, ascii_safe
from .core.schema import THEMES
from .kinds import erd as erd_kind
from .kinds.raw import to_drawio as raw_to_drawio

KINDS = {"raw": raw_to_drawio, "erd": erd_kind.to_drawio}


def build_parser():
    p = argparse.ArgumentParser(prog="diagram_tool", description="Convert a diagram JSON file to draw.io (.drawio).")
    p.add_argument("input", help="input JSON file")
    p.add_argument("-o", "--output", help="output file, or an existing directory (default: next to the input)")
    p.add_argument("--stdout", action="store_true", help="write the XML to standard output instead of a file")
    p.add_argument("--theme", choices=THEMES, help="override the theme of the document")
    p.add_argument("--kind", choices=sorted(KINDS), help="require this input kind (error if the file is another kind)")
    p.add_argument("--no-clobber", action="store_true", help="do not overwrite an existing output file")
    return p


def detect_kind(data):
    """'erd' for erd-meta-v1 (by structure), else the value of "kind" if it is a supported string."""
    if is_erd_meta(data):
        return "erd"
    if isinstance(data, dict) and "kind" not in data:
        raise ValidationError("missing required key 'kind'")
    kind = data.get("kind") if isinstance(data, dict) else None
    if not isinstance(kind, str) or kind not in KINDS or kind == "erd":
        raise ValidationError("unsupported kind (supported: raw, or an erd-meta-v1 file)", "kind")
    return kind


def convert(data, theme=None, kind=None):
    actual = detect_kind(data)
    if kind is not None and kind != actual:
        raise ValidationError("this file is kind '%s' but --kind %s was requested" % (actual, kind), "kind")
    return actual, KINDS[actual](data, theme)


def default_name(input_path, kind):
    base = os.path.splitext(os.path.basename(input_path))[0]
    if kind == "erd":
        if base.lower().endswith(".meta"):
            base = base[:-5]
        return base + ".gen.drawio"
    return base + ".drawio"


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
        kind, (xml, warnings) = convert(data, args.theme, args.kind)
        for message in warnings:
            sys.stderr.write("warning: %s\n" % ascii_safe(message))
        if args.stdout:
            sys.stdout.buffer.write(xml.encode("utf-8"))
            sys.stdout.buffer.flush()
        else:
            name = default_name(args.input, kind)
            if args.output and os.path.isdir(args.output):
                out = os.path.join(args.output, name)
            elif args.output:
                if args.output.endswith(("/", "\\")):
                    raise InputError("output directory does not exist: %s" % args.output)
                out = args.output
            else:
                out = os.path.join(os.path.dirname(args.input), name)
            if _same_file(out, args.input):
                raise InputError("output would overwrite the input file: %s" % out)
            if args.no_clobber and os.path.exists(out):
                sys.stderr.write("skipped: %s\n" % ascii_safe(out))
            else:
                write_atomic(out, xml)
                sys.stderr.write("wrote: %s\n" % ascii_safe(out))
    except DiagramError as exc:
        sys.stderr.write("error: %s\n" % exc)
        return exc.exit_code
    return 0


if __name__ == "__main__":
    sys.exit(main())
