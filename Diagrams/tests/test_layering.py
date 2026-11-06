import itertools
import os
import random
import time
import unittest

from diagram_tool.adapters import erd_meta_v1 as A
from diagram_tool.algo import netsimplex
from diagram_tool.algo.cycles import feedback_edges, vertex_order
from diagram_tool.algo.layering import assign_layers
from diagram_tool.core import jsonio

from tests.test_erd_adapter import REAL_META


def is_acyclic(n, edges, flags):
    oriented = [(v, u) if f else (u, v) for (u, v, _), f in zip(edges, flags)]
    indeg = [0] * n
    out = [[] for _ in range(n)]
    for u, v in oriented:
        out[u].append(v)
        indeg[v] += 1
    queue = [x for x in range(n) if indeg[x] == 0]
    seen = 0
    while queue:
        x = queue.pop()
        seen += 1
        for y in out[x]:
            indeg[y] -= 1
            if indeg[y] == 0:
                queue.append(y)
    return seen == n


def brute_force_min(n, edges):
    best = None
    for ranks in itertools.product(range(n), repeat=n):
        if min(ranks) != 0:
            continue
        if all(ranks[v] - ranks[u] >= m for u, v, m, _ in edges):
            c = netsimplex.cost(edges, ranks)
            if best is None or c < best:
                best = c
    return best


def random_connected_dag(rng, n, extra):
    perm = list(range(n))
    rng.shuffle(perm)
    edges = []
    seen = set()
    for i in range(1, n):
        j = rng.randrange(i)
        u, v = perm[j], perm[i]
        edges.append((u, v, 1, rng.randint(1, 8)))
        seen.add((u, v))
    for _ in range(extra):
        i, j = sorted(rng.sample(range(n), 2))
        u, v = perm[i], perm[j]
        if (u, v) not in seen:
            seen.add((u, v))
            edges.append((u, v, 1, rng.randint(1, 8)))
    return edges


class CyclesTest(unittest.TestCase):
    def test_dag_is_untouched(self):
        edges = [(0, 1, 1), (1, 2, 1), (0, 2, 5)]
        self.assertEqual(feedback_edges(3, edges), [False, False, False])

    def test_ring_reverses_the_lightest_edge(self):
        edges = [(0, 1, 5), (1, 2, 4), (2, 0, 1)]
        self.assertEqual(feedback_edges(3, edges), [False, False, True])
        self.assertEqual(vertex_order(3, edges), [0, 1, 2])

    def test_two_cycle_reverses_the_lighter_edge(self):
        edges = [(0, 1, 4), (1, 0, 1)]        # khu_tap_trung -> co_so (4) vs co_so -> khu_tap_trung (1)
        self.assertEqual(feedback_edges(2, edges), [False, True])
        self.assertEqual(feedback_edges(2, edges[::-1]), [True, False])

    def test_equal_weights_tie_breaks_by_index(self):
        self.assertEqual(feedback_edges(2, [(0, 1, 3), (1, 0, 3)]), [False, True])
        self.assertEqual(feedback_edges(2, [(1, 0, 3), (0, 1, 3)]), [True, False])   # vertex 0 always goes first

    def test_always_acyclic_on_random_graphs(self):
        rng = random.Random(7)
        for _ in range(200):
            n = rng.randint(2, 9)
            edges = []
            for _ in range(rng.randint(1, 20)):
                u, v = rng.sample(range(n), 2)
                edges.append((u, v, rng.randint(1, 8)))
            flags = feedback_edges(n, edges)
            self.assertTrue(is_acyclic(n, edges, flags), (n, edges))

    def test_deterministic(self):
        edges = [(0, 1, 2), (1, 2, 2), (2, 0, 2), (2, 3, 1), (3, 1, 1)]
        self.assertEqual(feedback_edges(4, edges), feedback_edges(4, edges))


class NetworkSimplexTest(unittest.TestCase):
    def test_chain_and_single(self):
        self.assertEqual(netsimplex.rank_nodes(1, []), [0])
        self.assertEqual(netsimplex.rank_nodes(3, [(0, 1, 1, 1), (1, 2, 1, 1)]), [0, 1, 2])

    def test_long_edge_pulls_nodes_together(self):
        # a->b, b->c, a->c(10): c - a must be 2
        edges = [(0, 1, 1, 1), (1, 2, 1, 1), (0, 2, 1, 10)]
        self.assertEqual(netsimplex.rank_nodes(3, edges), [0, 1, 2])

    def test_heavy_edge_gets_short(self):
        # diamond a->b->d, a->c->d plus c->e(1), a->e(9): e should sit right below a? e must be >= 1.
        edges = [(0, 1, 1, 1), (1, 3, 1, 1), (0, 2, 1, 1), (2, 3, 1, 1), (0, 4, 1, 9), (4, 3, 1, 1)]
        ranks = netsimplex.rank_nodes(5, edges)
        self.assertEqual(ranks[4] - ranks[0], 1)
        self.assertEqual(min(ranks), 0)

    def test_balance_moves_equal_weight_node_to_emptier_layer(self):
        # a->b->c->d, a->f->c, a->e->d : e is free in rank 1..2, layer 1 has {b, f}, layer 2 has {c}
        a, b, c, d, f, e = range(6)
        edges = [(a, b, 1, 1), (b, c, 1, 1), (c, d, 1, 1), (a, f, 1, 1), (f, c, 1, 1), (a, e, 1, 1), (e, d, 1, 1)]
        ranks = netsimplex.rank_nodes(6, edges)
        self.assertEqual(ranks, [0, 1, 2, 3, 1, 2])
        unbalanced = netsimplex.rank_nodes(6, edges, balance=False)
        self.assertEqual(netsimplex.cost(edges, ranks), netsimplex.cost(edges, unbalanced))

    def test_optimal_against_brute_force(self):
        rng = random.Random(2026)
        for trial in range(60):
            n = rng.randint(2, 5) if trial < 50 else 6
            edges = random_connected_dag(rng, n, rng.randint(0, 4))
            ranks = netsimplex.rank_nodes(n, edges)
            self.assertTrue(all(ranks[v] - ranks[u] >= m for u, v, m, _ in edges), (edges, ranks))
            self.assertEqual(min(ranks), 0)
            self.assertEqual(netsimplex.cost(edges, ranks), brute_force_min(n, edges), (edges, ranks))

    def test_against_linprog_when_scipy_is_available(self):
        try:
            from scipy.optimize import linprog
        except Exception:
            self.skipTest("scipy not available")
        rng = random.Random(11)
        for _ in range(15):
            n = rng.randint(8, 14)
            edges = random_connected_dag(rng, n, rng.randint(3, 10))
            ranks = netsimplex.rank_nodes(n, edges)
            c = [0.0] * n
            for u, v, _, w in edges:
                c[v] += w
                c[u] -= w
            a_ub = []
            b_ub = []
            for u, v, m, _ in edges:
                row = [0.0] * n
                row[u], row[v] = 1.0, -1.0
                a_ub.append(row)
                b_ub.append(-float(m))
            res = linprog(c, A_ub=a_ub, b_ub=b_ub, bounds=[(0, None)] * n, method="highs")
            self.assertTrue(res.success)
            self.assertAlmostEqual(netsimplex.cost(edges, ranks), res.fun, places=6)

    def test_iteration_cap_falls_back_to_longest_path(self):
        edges = [(0, 1, 1, 1), (1, 2, 1, 1), (0, 2, 1, 10)]
        ranks = netsimplex.rank_nodes(3, edges, max_iter=0, balance=False)
        self.assertEqual(ranks, netsimplex.longest_path_ranks(3, edges))

    def test_cycle_and_disconnected_inputs_are_rejected(self):
        with self.assertRaises(ValueError):
            netsimplex.rank_nodes(2, [(0, 1, 1, 1), (1, 0, 1, 1)])
        with self.assertRaises(ValueError):
            netsimplex.rank_nodes(3, [(0, 1, 1, 1)])

    def test_deterministic(self):
        rng = random.Random(5)
        edges = random_connected_dag(rng, 12, 8)
        self.assertEqual(netsimplex.rank_nodes(12, edges), netsimplex.rank_nodes(12, list(edges)))


class LayeringTest(unittest.TestCase):
    def test_chain_diamond_and_isolated(self):
        r = assign_layers(6, [(0, 1, 4), (1, 2, 4), (0, 3, 4), (3, 2, 4)])
        self.assertEqual(r["rank"][:4], [0, 1, 2, 1])
        self.assertEqual(r["components"], [[0, 1, 2, 3], [4], [5]])
        self.assertEqual(r["rank"][4:], [0, 0])
        self.assertEqual(r["reversed"], [False] * 4)

    def test_tree_gets_fixed_ranks(self):
        # root 0 with children 1, 2; 1 has child 3
        r = assign_layers(4, [(0, 1, 4), (0, 2, 4), (1, 3, 4)])
        self.assertEqual(r["rank"], [0, 1, 1, 2])

    def test_three_cycle_through_layering(self):
        r = assign_layers(3, [(0, 1, 5), (1, 2, 4), (2, 0, 1)])
        self.assertEqual(r["reversed"], [False, False, True])
        self.assertEqual(r["rank"], [0, 1, 2])

    def test_components_largest_first(self):
        r = assign_layers(5, [(3, 4, 1), (0, 1, 1), (1, 2, 1)])
        self.assertEqual(r["components"], [[0, 1, 2], [3, 4]])

    def test_self_loops_ignored(self):
        r = assign_layers(2, [(0, 0, 4), (0, 1, 4)])
        self.assertEqual(r["rank"], [0, 1])
        self.assertEqual(r["reversed"], [False, False])

    def test_parallel_edges_merge(self):
        r = assign_layers(3, [(0, 1, 1), (0, 1, 1), (1, 2, 1), (0, 2, 1)])
        self.assertEqual(r["rank"], [0, 1, 2])

    def test_two_cycle_puts_the_heavier_parent_on_top(self):
        # 0 = khu_tap_trung, 1 = co_so; khu->co_so weight 4, co_so->khu weight 1, plus a child of co_so
        r = assign_layers(3, [(0, 1, 4), (1, 0, 1), (1, 2, 4)])
        self.assertEqual(r["reversed"], [False, True, False])
        self.assertEqual(r["rank"], [0, 1, 2])

    def test_every_non_loop_edge_is_respected_after_reversal(self):
        rng = random.Random(99)
        for _ in range(100):
            n = rng.randint(2, 12)
            edges = [(*rng.sample(range(n), 2), rng.choice((1, 4, 8))) for _ in range(rng.randint(1, 25))]
            r = assign_layers(n, edges)
            for (u, v, _), flip in zip(edges, r["reversed"]):
                a, b = (v, u) if flip else (u, v)
                self.assertGreaterEqual(r["rank"][b] - r["rank"][a], 1, (n, edges))
            for members in r["components"]:
                self.assertEqual(min(r["rank"][v] for v in members), 0)

    def test_performance_60_nodes(self):
        rng = random.Random(3)
        n = 60
        edges = []
        for i in range(1, n):
            edges.append((rng.randrange(i), i, rng.choice((1, 4, 8))))
        for _ in range(60):
            u, v = rng.sample(range(n), 2)
            edges.append((u, v, rng.choice((1, 4, 8))))
        start = time.time()
        assign_layers(n, edges)
        self.assertLess(time.time() - start, 5.0)

    def test_deterministic(self):
        edges = [(0, 1, 4), (1, 0, 1), (1, 2, 4), (3, 1, 1)]
        self.assertEqual(assign_layers(4, edges), assign_layers(4, list(edges)))


@unittest.skipUnless(os.path.exists(REAL_META), "real erd_mau_02.meta.json not available")
class RealDataLayeringTest(unittest.TestCase):
    def test_real_data(self):
        model = A.parse_erd_meta(jsonio.load_file(REAL_META))
        names = [t["name"] for t in model["tables"]]
        index = {n: i for i, n in enumerate(names)}
        edges = [(index[r["parent"]], index[r["child"]], r["weight"]) for r in model["relations"]]
        res = assign_layers(len(names), edges)
        rank = res["rank"]
        reversed_ids = [r["id"] for r, f in zip(model["relations"], res["reversed"]) if f]
        self.assertEqual(reversed_ids, ["rel.khu_tap_trung.co_so_ha_tang_id"])
        self.assertLess(rank[index["khu_tap_trung"]], rank[index["co_so"]])
        for (u, v, _), flip in zip(edges, res["reversed"]):
            a, b = (v, u) if flip else (u, v)
            self.assertGreaterEqual(rank[b] - rank[a], 1)
        self.assertEqual(len(res["components"]), 1)
        self.assertEqual(min(rank), 0)


if __name__ == "__main__":
    unittest.main()
