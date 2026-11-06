"""Vertex ordering inside layers: dummy nodes, median sweeps, transpose, crossing count.

order_layers(nodes, rank, edges, iterations=24) works on ONE connected component.

  nodes   list of node ids (ints), rank[node] -> layer index (consecutive from 0 within the component)
  edges   list of (u, v, w) with rank[v] > rank[u] (already oriented; no self-loops). Each edge
          gets its own chain of dummy nodes (parallel edges are kept apart for routing).

Returns {"layers": [[node...]...], "chains": [[node...] per edge], "crossings": int,
         "initial_crossings": int, "dummies": int}. Dummy node ids start at max(nodes) + 1 and are
handed out in edge order, so the result is deterministic. The order within a layer is the
left-to-right order. Ties are broken by (current position, id); nothing iterates a set.
"""


def _inversions(seq):
    """Number of pairs i < j with seq[i] > seq[j] (strict), via a Fenwick tree."""
    if not seq:
        return 0
    top = max(seq) + 2
    tree = [0] * (top + 1)
    total = 0
    seen = 0
    for x in seq:
        # count previous values strictly greater than x
        i = x + 1
        le = 0
        while i > 0:
            le += tree[i]
            i -= i & -i
        total += seen - le
        i = x + 1
        while i <= top:
            tree[i] += 1
            i += i & -i
        seen += 1
    return total


def count_crossings(layers, links):
    """links: list of (upper_node, lower_node) between ADJACENT layers (any layer pair).

    Edges that share an endpoint never cross. Returns the total number of crossings.
    """
    pos = {}
    layer_of = {}
    for li, layer in enumerate(layers):
        for p, v in enumerate(layer):
            pos[v] = p
            layer_of[v] = li
    groups = {}
    for u, v in links:
        groups.setdefault(layer_of[u], []).append((pos[u], pos[v]))
    total = 0
    for li in sorted(groups):
        pairs = sorted(groups[li])
        total += _inversions([b for _, b in pairs])
    return total


def order_layers(nodes, rank, edges, iterations=24, first_dummy_id=None):
    """`first_dummy_id` (default max(nodes)+1) lets the caller keep dummy ids globally unique
    when several components are ordered separately."""
    nodes = list(nodes)
    next_id = first_dummy_id if first_dummy_id is not None else ((max(nodes) + 1) if nodes else 0)
    if nodes and next_id <= max(nodes):
        raise ValueError("first_dummy_id collides with node ids")
    for u, v, _ in edges:
        if rank[v] <= rank[u]:
            raise ValueError("edge (%r, %r) does not point to a deeper layer" % (u, v))
    base = min(rank[v] for v in nodes) if nodes else 0
    depth = (max(rank[v] for v in nodes) - base + 1) if nodes else 0
    layer_of = {v: rank[v] - base for v in nodes}
    chains = []
    links = []                   # (upper, lower) between adjacent layers, weight
    dummies = 0
    for u, v, w in edges:
        chain = [u]
        for r in range(layer_of[u] + 1, layer_of[v]):
            d = next_id
            next_id += 1
            dummies += 1
            layer_of[d] = r
            chain.append(d)
        chain.append(v)
        chains.append(chain)
        for a, b in zip(chain, chain[1:]):
            links.append((a, b))

    up = {}
    down = {}
    for a, b in links:
        down.setdefault(a, []).append(b)
        up.setdefault(b, []).append(a)
    all_nodes = nodes + [d for chain in chains for d in chain[1:-1]]
    degree = {x: len(up.get(x, [])) + len(down.get(x, [])) for x in all_nodes}

    # ---- initial order: DFS following down links from the most connected top nodes ----------
    layers = [[] for _ in range(depth)]
    placed = set()

    def dfs(start):
        stack = [start]
        while stack:
            x = stack.pop()
            if x in placed:
                continue
            placed.add(x)
            layers[layer_of[x]].append(x)
            for y in sorted(down.get(x, []), key=lambda t: (-degree[t], t), reverse=True):
                if y not in placed:
                    stack.append(y)

    for x in sorted(all_nodes, key=lambda t: (layer_of[t], -degree[t], t)):
        if x not in placed:
            dfs(x)

    def crossings_now():
        return count_crossings(layers, links)

    initial = crossings_now()
    best = initial
    best_layers = [list(layer) for layer in layers]

    def positions():
        return {v: p for layer in layers for p, v in enumerate(layer)}

    def sweep(order, neighbours):
        pos = positions()
        for li in order:
            keyed = []
            for p, v in enumerate(layers[li]):
                ns = sorted(pos[n] for n in neighbours.get(v, []))
                if ns:
                    k = len(ns)
                    med = ns[k // 2] if k % 2 else (ns[k // 2 - 1] + ns[k // 2]) / 2.0
                else:
                    med = float(p)
                keyed.append((med, p, v))
            keyed.sort()
            layers[li] = [v for _, _, v in keyed]
            for p, v in enumerate(layers[li]):
                pos[v] = p

    def pair_cross(v, w, pos):
        """Crossings between v (left) and w (right) over both adjacent layers."""
        c = 0
        for adj in (up, down):
            for a in adj.get(v, []):
                for b in adj.get(w, []):
                    if pos[a] > pos[b]:
                        c += 1
        return c

    def transpose():
        improved = True
        passes = 0
        while improved and passes < 20:
            improved = False
            passes += 1
            pos = positions()
            for layer in layers:
                for i in range(len(layer) - 1):
                    v, w = layer[i], layer[i + 1]
                    if pair_cross(v, w, pos) > pair_cross(w, v, pos):
                        layer[i], layer[i + 1] = w, v
                        pos[v], pos[w] = i + 1, i
                        improved = True

    for _ in range(iterations):
        sweep(range(1, depth), up)
        transpose()
        c = crossings_now()
        if c < best:
            best, best_layers = c, [list(layer) for layer in layers]
        sweep(range(depth - 2, -1, -1), down)
        transpose()
        c = crossings_now()
        if c < best:
            best, best_layers = c, [list(layer) for layer in layers]
        if best == 0:
            break
    return {"layers": best_layers, "chains": chains, "crossings": best, "initial_crossings": initial,
            "dummies": dummies}
