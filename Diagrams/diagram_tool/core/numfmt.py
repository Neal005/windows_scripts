"""Deterministic number formatting for XML output.

Integer when possible, otherwise one decimal digit (round half away from zero),
never "-0", never exponent notation. NaN/Inf and bool are rejected.
"""

import math
from decimal import Context, Decimal, ROUND_HALF_UP

_CTX = Context(prec=400)
_TENTH = Decimal("0.1")


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
