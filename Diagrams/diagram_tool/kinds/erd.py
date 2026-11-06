"""Kind `erd` (erd-meta-v1): meta.json -> adapter -> layout -> routes -> `raw` document -> draw.io XML."""

from ..adapters.erd_meta_v1 import build_raw_document, parse_erd_meta
from ..core.errors import ascii_safe
from ..emit.mxgraph import emit_document
from ..layout.erd_layout import compute_layout
from ..layout.erd_route import route_layout
from .raw import validate_raw


def layout_document(data):
    """Return (model, raw_document) for erd-meta-v1 `data` (input schema of kind raw)."""
    model = parse_erd_meta(data)
    layout = compute_layout(model)
    routed = route_layout(model, layout)
    doc = build_raw_document(model, routed["positions"], routed["widths"], routed["routes"])
    return model, doc


def to_drawio(data, theme=None):
    model, doc = layout_document(data)
    result = validate_raw(doc)
    xml = emit_document(result.doc, theme)
    warnings = tuple(ascii_safe(w) for w in model["warnings"]) + tuple(result.warnings)
    return xml, warnings
