"""Cycle removal: weighted Eades-Lin-Smyth.

feedback_edges(n, edges) -> set-free list of booleans: reversed[i] is True when edge i must be
reversed so that the graph becomes acyclic. edges are (u, v, w) with 0 <= u, v < n, u != v,
w > 0. The heuristic removes sinks (put last) and sources (put first) repeatedly; when neither
exists it puts the vertex with the largest (out weight - in weight) first. Every tie is broken
by the smallest vertex index, so the result is deterministic.
"""


def vertex_order(n, edges):
    out_w = [0] * n
    in_w = [0] * n
    out_adj = [[] for _ in range(n)]
    in_adj = [[] for _ in range(n)]
    for u, v, w in edges:
        out_w[u] += w
        in_w[v] += w
        out_adj[u].append((v, w))
        in_adj[v].append((u, w))
    out_cnt = [len(a) for a in out_adj]
    in_cnt = [len(a) for a in in_adj]
    alive = [True] * n
    left = []
    right = []          # sinks, in removal order (they end up last, in reverse removal order)
    remaining = n

    def remove(x):
        nonlocal remaining
        alive[x] = False
        remaining -= 1
        for y, w in out_adj[x]:
            if alive[y]:
                in_w[y] -= w
                in_cnt[y] -= 1
        for y, w in in_adj[x]:
            if alive[y]:
                out_w[y] -= w
                out_cnt[y] -= 1

    while remaining:
        changed = True
        while changed:
            changed = False
            for x in range(n):
                if alive[x] and out_cnt[x] == 0:
                    right.append(x)
                    remove(x)
                    changed = True
            for x in range(n):
                if alive[x] and in_cnt[x] == 0:
                    left.append(x)
                    remove(x)
                    changed = True
        if not remaining:
            break
        best = None
        for x in range(n):
            if alive[x]:
                delta = out_w[x] - in_w[x]
                if best is None or delta > best[0]:
                    best = (delta, x)
        left.append(best[1])
        remove(best[1])
    return left + right[::-1]


def feedback_edges(n, edges):
    order = vertex_order(n, edges)
    pos = [0] * n
    for i, v in enumerate(order):
        pos[v] = i
    return [pos[u] > pos[v] for u, v, _ in edges]
