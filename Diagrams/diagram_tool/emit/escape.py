"""XML attribute escaping for labels (html=0: plain text, newline as &#10;)."""

from xml.sax.saxutils import escape

from ..core.errors import ValidationError
from ..core.text import find_bad_char, normalize_newlines

_ENTITIES = {'"': "&quot;", "'": "&apos;", "\n": "&#10;", "\t": "&#9;"}


def escape_attr(text, path=""):
    """Escape `text` for use inside a double-quoted XML attribute value.

    & < > " ' are escaped, LF -> &#10;, TAB -> &#9;; CR/CRLF are normalised to LF.
    Other control characters are rejected. Non-ASCII text (Vietnamese) is kept as is.
    """
    if not isinstance(text, str):
        raise ValidationError("expected a string", path)
    text = normalize_newlines(text)
    bad = find_bad_char(text)
    if bad is not None:
        raise ValidationError("control character U+%04X at index %d is not allowed" % (ord(bad[1]), bad[0]), path)
    return escape(text, _ENTITIES)
