"""Typed errors. Every message is pure ASCII (non-ASCII characters are backslash-escaped)."""


def ascii_safe(text):
    return str(text).encode("ascii", "backslashreplace").decode("ascii")


class DiagramError(Exception):
    """Base error. `path` is a field path such as pages[0].cells[3].points[1]."""

    exit_code = 1

    def __init__(self, message, path=""):
        self.path = path
        self.message = message
        text = "%s: %s" % (path, message) if path else message
        super().__init__(ascii_safe(text))


class JsonError(DiagramError):
    """Malformed JSON (syntax, duplicate key, NaN/Inf, bad encoding)."""


class ValidationError(DiagramError):
    """The JSON is well formed but violates the diagram schema."""


class InputError(DiagramError):
    """Input/output problem (file missing, unreadable, unwritable)."""

    exit_code = 2
