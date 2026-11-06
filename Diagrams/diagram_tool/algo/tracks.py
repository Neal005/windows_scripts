"""Track (horizontal lane) assignment inside the gap between two layers.

assign_tracks(pieces) -> list of track indices (0 = topmost) for NON-straight pieces.
A piece is (x_u, x_l): an upper vertical stub at x_u from the top of the gap down to its track,
a horizontal run to x_l, then a lower vertical stub at x_l down to the bottom of the gap. All
x values of a gap are distinct (the router guarantees it), so no stub of one piece can coincide
with a stub of another.

Every pair of pieces whose horizontal intervals overlap (closed) gets an arc "P above Q",
oriented to minimise the stub/run crossings (ties: left interval first, then index); a cycle
among the arcs is removed with the weighted Eades-Lin-Smyth heuristic. Tracks are the longest
path levels of the resulting DAG, so two overlapping runs never share a track. Pieces whose
intervals do not overlap may share a track.
"""

from .cycles import feedback_edges
from .netsimplex import longest_path_ranks


def _crossings(above, below):
    """Crossings if piece `above` (smaller y) is drawn over piece `below`."""
    a_lo, a_hi = sorted(above)
    b_lo, b_hi = sorted(below)
    total = 0
    if a_lo < below[0] < a_hi:          # below's upper stub crosses above's run
        total += 1
    if b_lo < above[1] < b_hi:          # above's lower stub crosses below's run
        total += 1
    return total


def assign_tracks(pieces):
    m = len(pieces)
    arcs = []                           # (p, q, weight): p above q
    for p in range(m):
        p_lo, p_hi = sorted(pieces[p])
        for q in range(p + 1, m):
            q_lo, q_hi = sorted(pieces[q])
            if max(p_lo, q_lo) > min(p_hi, q_hi):
                continue
            c_pq = _crossings(pieces[p], pieces[q])
            c_qp = _crossings(pieces[q], pieces[p])
            if c_pq < c_qp:
                first_p = True
            elif c_qp < c_pq:
                first_p = False
            else:
                first_p = (p_lo, p) <= (q_lo, q)
            weight = 1 + abs(c_pq - c_qp)
            arcs.append((p, q, weight) if first_p else (q, p, weight))
    flags = feedback_edges(m, arcs)
    oriented = [((v, u, 1, 1) if f else (u, v, 1, 1)) for (u, v, _), f in zip(arcs, flags)]
    if m == 0:
        return []
    return longest_path_ranks(m, oriented)
