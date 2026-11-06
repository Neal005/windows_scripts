"""Network simplex ranking (Gansner et al., "A technique for drawing directed graphs").

rank_nodes(n, edges, max_iter=None) -> list of integer ranks, normalised to min 0.
edges: (u, v, minlen, weight) meaning rank[v] - rank[u] >= minlen, minimising
sum(weight * (rank[v] - rank[u])). The graph must be connected (as an undirected graph) and
acyclic (as a directed graph); the caller splits components and removes cycles.

This is the straightforward O(V*E)-per-iteration version (cut values are recomputed from the
tree each iteration), fine for ERD sizes. Pivot rule is fixed (smallest tree-edge index with
negative cut value; entering edge of minimum slack, ties by smallest edge index), so results
are deterministic. If `max_iter` is exceeded the longest-path ranking is returned (feasible,
not necessarily optimal).
"""


def longest_path_ranks(n, edges):
    indeg = [0] * n
    out = [[] for _ in range(n)]
    for u, v, minlen, _ in edges:
        out[u].append((v, minlen))
        indeg[v] += 1
    rank = [0] * n
    queue = [x for x in range(n) if indeg[x] == 0]
    seen = 0
    while queue:
        x = queue.pop(0)
        seen += 1
        for y, minlen in out[x]:
            rank[y] = max(rank[y], rank[x] + minlen)
            indeg[y] -= 1
            if indeg[y] == 0:
                queue.append(y)
    if seen != n:
        raise ValueError("graph has a cycle")
    return rank


def cost(edges, rank):
    return sum(w * (rank[v] - rank[u]) for u, v, _, w in edges)


def _slack(e, rank):
    u, v, minlen, _ = e
    return rank[v] - rank[u] - minlen


def _feasible_tree(n, edges, rank):
    """Shift ranks until a spanning tree of tight edges exists. Returns the set of tree edge indices."""
    in_tree = [False] * n
    in_tree[0] = True
    tree = []
    count = 1
    while count < n:
        grew = True
        while grew:
            grew = False
            for i, e in enumerate(edges):
                u, v = e[0], e[1]
                if in_tree[u] != in_tree[v] and _slack(e, rank) == 0:
                    in_tree[u] = in_tree[v] = True
                    tree.append(i)
                    count += 1
                    grew = True
        if count == n:
            break
        best = None
        for i, e in enumerate(edges):
            u, v = e[0], e[1]
            if in_tree[u] != in_tree[v]:
                s = _slack(e, rank)
                if best is None or s < best[0]:
                    best = (s, i)
        if best is None:
            raise ValueError("graph is not connected")
        s, i = best
        u, v = edges[i][0], edges[i][1]
        delta = s if in_tree[u] else -s      # move the tree so that the edge becomes tight
        for x in range(n):
            if in_tree[x]:
                rank[x] += delta
    return tree


def _split(n, edges, tree, removed):
    """Component (as a bool list) of edges[removed].tail after removing it from the tree."""
    adj = [[] for _ in range(n)]
    for i in tree:
        if i != removed:
            u, v = edges[i][0], edges[i][1]
            adj[u].append(v)
            adj[v].append(u)
    start = edges[removed][0]
    comp = [False] * n
    comp[start] = True
    stack = [start]
    while stack:
        x = stack.pop()
        for y in adj[x]:
            if not comp[y]:
                comp[y] = True
                stack.append(y)
    return comp


def _cut_value(edges, tail_comp, removed):
    total = 0
    for i, (u, v, _, w) in enumerate(edges):
        if tail_comp[u] and not tail_comp[v]:
            total += w
        elif tail_comp[v] and not tail_comp[u]:
            total -= w
    return total


def _balance(n, edges, rank):
    """Move nodes with equal in/out weight to the least populated feasible rank (ties: lowest)."""
    inw = [0] * n
    outw = [0] * n
    for u, v, _, w in edges:
        outw[u] += w
        inw[v] += w
    top = max(rank) if rank else 0
    count = [0] * (top + 1)
    for r in rank:
        count[r] += 1
    for x in range(n):
        if inw[x] != outw[x]:
            continue
        lo, hi = 0, top
        for u, v, minlen, _ in edges:
            if v == x:
                lo = max(lo, rank[u] + minlen)
            if u == x:
                hi = min(hi, rank[v] - minlen)
        if lo > hi:
            continue
        best = rank[x]
        for r in range(lo, hi + 1):
            if count[r] < count[best]:
                best = r
        if best != rank[x]:
            count[rank[x]] -= 1
            count[best] += 1
            rank[x] = best


def rank_nodes(n, edges, max_iter=None, balance=True):
    if n == 0:
        return []
    if n == 1:
        return [0]
    rank = longest_path_ranks(n, edges)
    limit = 100 * (len(edges) + n) if max_iter is None else max_iter
    result = list(rank)
    tree = _feasible_tree(n, edges, rank)
    for _ in range(limit):
        leave = None
        for i in sorted(tree):
            tail_comp = _split(n, edges, tree, i)
            if _cut_value(edges, tail_comp, i) < 0:
                leave = (i, tail_comp)
                break
        if leave is None:
            result = rank
            break
        i, tail_comp = leave
        enter = None
        for j, e in enumerate(edges):
            u, v = e[0], e[1]
            if not tail_comp[u] and tail_comp[v] and j not in tree:   # head component -> tail component
                s = _slack(e, rank)
                if enter is None or s < enter[0]:
                    enter = (s, j)
        if enter is None:
            break
        s, j = enter
        for x in range(n):
            if tail_comp[x]:
                rank[x] -= s
        tree = [t for t in tree if t != i] + [j]
    else:
        result = longest_path_ranks(n, edges)    # iteration cap reached: feasible, maybe not optimal
    low = min(result)
    result = [r - low for r in result]
    if balance:
        _balance(n, edges, result)
        low = min(result)
        result = [r - low for r in result]
    return result
