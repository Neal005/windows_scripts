"""Id helpers: syntax check, slug from a label, collision-free suffixes, composed cell ids."""

import re
import unicodedata

_ID_RE = re.compile(r"^[^\s:\x00-\x1f\x7f-\x9f]{1,200}\Z")
_NON_ALNUM = re.compile(r"[^a-z0-9]+")


def is_valid_id(value):
    """JSON ids: 1..200 chars, no whitespace, no control chars, no ':' (reserved separator)."""
    return isinstance(value, str) and _ID_RE.match(value) is not None


def slug(label):
    """Deterministic ASCII slug: strip Vietnamese diacritics (NFKD, d-stroke -> d), lower case."""
    text = label.replace("\u0111", "d").replace("\u0110", "D")
    text = unicodedata.normalize("NFKD", text)
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = _NON_ALNUM.sub("_", text.lower()).strip("_")
    return text


def unique_id(base, used):
    """Return base, or base_2, base_3... not in `used` (a set, only membership is tested); adds it."""
    candidate = base
    n = 2
    while candidate in used:
        candidate = "%s_%d" % (base, n)
        n += 1
    used.add(candidate)
    return candidate


def cell_id(page_id, local_id):
    return "%s:%s" % (page_id, local_id)


def child_id(parent_cell_id, local_id):
    """Composed id of a table row or edge label: <ownerCellId>:<localId>."""
    return "%s:%s" % (parent_cell_id, local_id)
