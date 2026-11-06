"""Deterministic number formatting for XML output.

Integer when possible, otherwise one decimal digit (round half away from zero),
never "-0", never exponent notation. NaN/Inf and bool are rejected.
"""

import math
from decimal import Context, Decimal, ROUND_HALF_UP

_CTX = Context(prec=400)
_TENTH = Decimal("0.1")


_TEN_THOUSANDTH = Decimal("0.0001")


def fmt_ratio(value):
    """Port/anchor fractions (exitX, entryY ...): up to 4 decimals, trailing zeros stripped."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise TypeError("fmt_ratio() needs an int or float, got %s" % type(value).__name__)
    if isinstance(value, float) and not math.isfinite(value):
        raise ValueError("fmt_ratio() needs a finite number")
    d = Decimal(repr(value)).quantize(_TEN_THOUSANDTH, rounding=ROUND_HALF_UP, context=_CTX)
    text = format(d, "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return "0" if text in ("", "-0") else text


def fmt(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise TypeError("fmt() needs an int or float, got %s" % type(value).__name__)
    if isinstance(value, int):
        return str(value)
    if not math.isfinite(value):
        raise ValueError("fmt() needs a finite number")
    d = Decimal(repr(value)).quantize(_TENTH, rounding=ROUND_HALF_UP, context=_CTX)
    if d == d.to_integral_value():
        return str(int(d))  # int(Decimal('-0.0')) == 0, so "-0" cannot appear
    return format(d, "f")
