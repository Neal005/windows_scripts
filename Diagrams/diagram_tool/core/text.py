"""Text validity helpers shared by the validator and the XML escaper."""

import re

# Control characters other than TAB/LF (CR is normalised away first), C1 controls,
# lone surrogates and the XML non-characters U+FFFE/U+FFFF.
_BAD = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\ud800-\udfff￾￿]")


def normalize_newlines(text):
    return text.replace("\r\n", "\n").replace("\r", "\n")


def find_bad_char(text):
    """Return (index, char) of the first character not allowed in a label, or None."""
    m = _BAD.search(text)
    if m is None:
        return None
    return m.start(), m.group()
