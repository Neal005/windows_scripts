"""Layer (rank) assignment for a directed multigraph: components, cycle removal, network simplex.

assign_layers(n, edges) -> {"rank": [...], "components": [[node...]...], "reversed": [bool per edge]}
edges: (u, v, weight) with weight > 0; self-loops (u == v) are ignored (rank-free, reversed False).
Parallel edges between the same ordered pair are merged (weights added) for ranking.
Components are the undirected connected components; each is ranked independently (min rank 0)
and listed largest first (ties: smallest first node index). Isolated nodes form their own
components of size 1. reversed[i] is True when edge i points from a deeper to a shallower rank
because cycle removal reversed it (its drawing direction is restored when emitting).
"""

from .cycles import feedback_edges
from .netsimplex import rank_nodes


def _components(n, edges):
    adj = [[] for _ in range(n)]
    for u, v, _ in edges:
        if u != v:
            adj[u].append(v)
            adj[v].append(u)
    comp_of = [-1] * n
    comps = []
    for s in range(n):
        if comp_of[s] != -1:
            continue
        comp_of[s] = len(comps)
        members = [s]
        stack = [s]
        while stack:
            x = stack.pop()
            for y in adj[x]:
                if comp_of[y] == -1:
                    comp_of[y] = len(comps)
                    members.append(y)
                    stack.append(y)
        comps.append(sorted(members))
    return comps


def assign_layers(n, edges):
    comps = _components(n, edges)
    order = sorted(range(len(comps)), key=lambda c: (-len(comps[c]), comps[c][0]))
    comps = [comps[c] for c in order]
    rank = [0] * n
    reversed_flags = [False] * len(edges)
    for members in comps:
        index = {v: i for i, v in enumerate(members)}
        local = [(k, e) for k, e in enumerate(edges) if e[0] != e[1] and e[0] in index]
        if len(members) == 1:
            continue
        # merge parallel edges per ordered pair for cycle removal
        pair_w = {}
        pair_order = []
        for k, (u, v, w) in local:
            key = (index[u], index[v])
            if key not in pair_w:
                pair_w[key] = 0
                pair_order.append(key)
            pair_w[key] += w
        merged = [(a, b, pair_w[(a, b)]) for a, b in pair_order]
        flags = feedback_edges(len(members), merged)
        flip = {pair_order[i]: flags[i] for i in range(len(pair_order))}
        for k, (u, v, w) in local:
            reversed_flags[k] = flip[(index[u], index[v])]
        # oriented, merged again (a reversed pair may coincide with an opposite pair)
        oriented = {}
        oriented_order = []
        for (a, b), w in ((p, pair_w[p]) for p in pair_order):
            key = (b, a) if flip[(a, b)] else (a, b)
            if key not in oriented:
                oriented[key] = 0
                oriented_order.append(key)
            oriented[key] += w
        ns_edges = [(a, b, 1, oriented[(a, b)]) for a, b in oriented_order]
        ranks = rank_nodes(len(members), ns_edges)
        for v, r in zip(members, ranks):
            rank[v] = r
    return {"rank": rank, "components": comps, "reversed": reversed_flags}
