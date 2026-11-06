"""Strict JSON reading: utf-8-sig, duplicate keys rejected, NaN/Infinity rejected."""

import json
import math

from .errors import InputError, JsonError


def _reject_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise JsonError("duplicate key %s" % json.dumps(key))
        result[key] = value
    return result


def _reject_constant(name):
    raise JsonError("%s is not allowed" % name)


def _parse_float(text):
    value = float(text)
    if not math.isfinite(value):
        raise JsonError("number out of range: %s" % text)
    return value


def loads_bytes(data):
    """Decode UTF-8 (BOM tolerated) and parse. Raises JsonError."""
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise JsonError("input is not valid UTF-8 (byte offset %d)" % exc.start)
    try:
        return json.loads(
            text,
            object_pairs_hook=_reject_duplicates,
            parse_constant=_reject_constant,
            parse_float=_parse_float,
        )
    except JsonError:
        raise
    except json.JSONDecodeError as exc:
        raise JsonError("invalid JSON at line %d column %d: %s" % (exc.lineno, exc.colno, exc.msg))
    except RecursionError:
        raise JsonError("JSON nesting is too deep")


def load_file(path):
    """Read and parse a JSON file. Raises InputError (I/O) or JsonError (content)."""
    try:
        with open(path, "rb") as handle:
            data = handle.read()
    except OSError as exc:
        raise InputError("cannot read %s: %s" % (path, exc.strerror or exc))
    return loads_bytes(data)
