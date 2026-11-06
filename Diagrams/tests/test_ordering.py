import itertools
import os
import random
import time
import unittest

from diagram_tool.adapters import erd_meta_v1 as A
from diagram_tool.algo.layering import assign_layers
from diagram_tool.algo.ordering import count_crossings, order_layers
from diagram_tool.core import jsonio

from tests.test_erd_adapter import REAL_META


def brute_crossings(layers, links):
    pos = {v: p for layer in layers for p, v in enumerate(layer)}
    layer_of = {v: i for i, layer in enumerate(layers) for v in layer}
    total = 0
    for (a, b), (c, d) in itertools.combinations(links, 2):
        if layer_of[a] != layer_of[c]:
            continue
        if (pos[a] - pos[c]) * (pos[b] - pos[d]) < 0:
            total += 1
    return total


def links_of(result):
    return [(a, b) for chain in result["chains"] for a, b in zip(chain, chain[1:])]


def random_layered(rng, n, per_layer_edges):
    """Random layered DAG: returns nodes, rank, edges (u, v, w) with rank[v] > rank[u]."""
    layers = rng.randint(2, 5)
    rank = {v: rng.randrange(layers) for v in range(n)}
    edges = []
    for _ in range(per_layer_edges):
        u, v = rng.sample(range(n), 2)
        if rank[u] == rank[v]:
            continue
        if rank[u] > rank[v]:
            u, v = v, u
        edges.append((u, v, rng.choice((1, 4, 8))))
    used = sorted({x for e in edges for x in e[:2]})
    if not used:
        return [], {}, []
    low = min(rank[x] for x in used)
    return used, {x: rank[x] - low for x in used}, edges


class CrossingCountTest(unittest.TestCase):
    def test_known_counts(self):
        layers = [["a", "b"], ["c", "d"]]
        self.assertEqual(count_crossings(layers, [("a", "c"), ("b", "d")]), 0)
        self.assertEqual(count_crossings(layers, [("a", "d"), ("b", "c")]), 1)
        self.assertEqual(count_crossings(layers, [("a", "c"), ("a", "d"), ("b", "c"), ("b", "d")]), 1)   # K2,2
        self.assertEqual(count_crossings(layers, [("a", "c"), ("a", "d")]), 0)          # shared endpoint
        self.assertEqual(count_crossings(layers, [("a", "d"), ("a", "d")]), 0)          # parallel edges
        self.assertEqual(count_crossings([["a"], ["b"]], []), 0)

    def test_matches_brute_force(self):
        rng = random.Random(4)
        for _ in range(100):
            top = ["t%d" % i for i in range(rng.randint(1, 6))]
            bottom = ["b%d" % i for i in range(rng.randint(1, 6))]
            rng.shuffle(top)
            rng.shuffle(bottom)
            links = [(rng.choice(top), rng.choice(bottom)) for _ in range(rng.randint(0, 14))]
            self.assertEqual(count_crossings([top, bottom], links), brute_crossings([top, bottom], links))

    def test_multiple_layer_pairs_add_up(self):
        layers = [["a", "b"], ["c", "d"], ["e", "f"]]
        links = [("a", "d"), ("b", "c"), ("c", "f"), ("d", "e")]
        self.assertEqual(count_crossings(layers, links), 2)


class OrderLayersTest(unittest.TestCase):
    def test_dummy_chains(self):
        res = order_layers([0, 1, 2], {0: 0, 1: 1, 2: 3}, [(0, 1, 1), (0, 2, 1), (1, 2, 1)])
        self.assertEqual(res["chains"][0], [0, 1])
        self.assertEqual(len(res["chains"][1]), 4)               # 0 -> d -> d -> 2 : two dummies
        self.assertEqual(res["chains"][1][0], 0)
        self.assertEqual(res["chains"][1][-1], 2)
        self.assertEqual(len(res["chains"][2]), 3)               # 1 -> dummy -> 2
        self.assertEqual(res["dummies"], 3)
        self.assertEqual(sum(len(layer) for layer in res["layers"]), 3 + 3)
        dummy_ids = [d for c in res["chains"] for d in c[1:-1]]
        self.assertEqual(len(dummy_ids), len(set(dummy_ids)))
        self.assertTrue(all(d > 2 for d in dummy_ids))

    def test_layers_contain_every_node_once_and_respect_ranks(self):
        rng = random.Random(8)
        for _ in range(40):
            nodes, rank, edges = random_layered(rng, rng.randint(3, 14), rng.randint(2, 30))
            if not edges:
                continue
            res = order_layers(nodes, rank, edges)
            flat = [v for layer in res["layers"] for v in layer]
            self.assertEqual(len(flat), len(set(flat)))
            self.assertTrue(set(nodes) <= set(flat))
            for li, layer in enumerate(res["layers"]):
                for v in layer:
                    if v in rank:
                        self.assertEqual(rank[v], li)
            for chain, (u, v, _) in zip(res["chains"], edges):
                self.assertEqual((chain[0], chain[-1]), (u, v))
                self.assertEqual(len(chain), rank[v] - rank[u] + 1)

    def test_reported_crossings_are_correct(self):
        rng = random.Random(21)
        for _ in range(40):
            nodes, rank, edges = random_layered(rng, rng.randint(3, 14), rng.randint(2, 30))
            if not edges:
                continue
            res = order_layers(nodes, rank, edges)
            self.assertEqual(res["crossings"], brute_crossings(res["layers"], links_of(res)))
            self.assertLessEqual(res["crossings"], res["initial_crossings"])

    def test_planar_graphs_reach_zero(self):
        # two chains that a naive order interleaves, and a tree
        res = order_layers([0, 1, 2, 3], {0: 0, 1: 0, 2: 1, 3: 1}, [(0, 3, 1), (1, 2, 1)])
        self.assertEqual(res["crossings"], 0)
        tree = [(0, 1, 1), (0, 2, 1), (1, 3, 1), (1, 4, 1), (2, 5, 1), (2, 6, 1)]
        res = order_layers(list(range(7)), {0: 0, 1: 1, 2: 1, 3: 2, 4: 2, 5: 2, 6: 2}, tree)
        self.assertEqual(res["crossings"], 0)

    def test_k22_has_exactly_one_crossing(self):
        res = order_layers([0, 1, 2, 3], {0: 0, 1: 0, 2: 1, 3: 1},
                           [(0, 2, 1), (0, 3, 1), (1, 2, 1), (1, 3, 1)])
        self.assertEqual(res["crossings"], 1)

    def test_more_iterations_never_worse(self):
        rng = random.Random(5)
        for _ in range(25):
            nodes, rank, edges = random_layered(rng, 12, 28)
            if not edges:
                continue
            few = order_layers(nodes, rank, edges, iterations=1)["crossings"]
            many = order_layers(nodes, rank, edges, iterations=24)["crossings"]
            self.assertLessEqual(many, few)

    def test_known_minimum_found_on_ladder(self):
        # layer0: a b c ; layer1: d e f ; edges a-f, b-e, c-d would cross 3 times if kept; reorder gives 0
        res = order_layers(list(range(6)), {0: 0, 1: 0, 2: 0, 3: 1, 4: 1, 5: 1},
                           [(0, 5, 1), (1, 4, 1), (2, 3, 1)])
        self.assertEqual(res["crossings"], 0)

    def test_deterministic(self):
        rng = random.Random(13)
        nodes, rank, edges = random_layered(rng, 14, 30)
        self.assertEqual(order_layers(nodes, rank, edges), order_layers(list(nodes), dict(rank), list(edges)))

    def test_parallel_edges_get_separate_chains_without_crossing_each_other(self):
        res = order_layers([0, 1], {0: 0, 1: 2}, [(0, 1, 1), (0, 1, 1)])
        self.assertEqual(res["dummies"], 2)
        self.assertEqual(res["crossings"], 0)

    def test_input_checks_and_dummy_offset(self):
        with self.assertRaises(ValueError):
            order_layers([0, 1], {0: 1, 1: 1}, [(0, 1, 1)])          # same layer
        with self.assertRaises(ValueError):
            order_layers([0, 1], {0: 2, 1: 0}, [(0, 1, 1)])          # points upwards
        res = order_layers([0, 1], {0: 0, 1: 2}, [(0, 1, 1)], first_dummy_id=500)
        self.assertEqual(res["chains"][0], [0, 500, 1])
        with self.assertRaises(ValueError):
            order_layers([0, 1], {0: 0, 1: 2}, [(0, 1, 1)], first_dummy_id=1)

    def test_equal_medians_keep_current_order(self):
        # two nodes with the same single parent: relative order is stable (ties by position)
        res = order_layers([0, 1, 2], {0: 0, 1: 1, 2: 1}, [(0, 1, 1), (0, 2, 1)])
        self.assertEqual(res["layers"], [[0], [1, 2]])

    def test_empty_and_single(self):
        self.assertEqual(order_layers([], {}, [])["layers"], [])
        res = order_layers([7], {7: 3}, [])
        self.assertEqual(res["layers"], [[7]])

    def test_performance_60_nodes(self):
        rng = random.Random(3)
        n = 60
        rank = {v: v // 6 for v in range(n)}
        edges = []
        for v in range(6, n):
            edges.append((rng.randrange((v // 6) * 6 - 6, (v // 6) * 6), v, 1))
        for _ in range(60):
            u, v = rng.sample(range(n), 2)
            if rank[u] < rank[v]:
                edges.append((u, v, 1))
        start = time.time()
        order_layers(list(range(n)), rank, edges)
        self.assertLess(time.time() - start, 5.0)


@unittest.skipUnless(os.path.exists(REAL_META), "real erd_mau_02.meta.json not available")
class RealDataOrderingTest(unittest.TestCase):
    def test_real_data_ordering(self):
        model = A.parse_erd_meta(jsonio.load_file(REAL_META))
        names = [t["name"] for t in model["tables"]]
        index = {n: i for i, n in enumerate(names)}
        raw = [(index[r["parent"]], index[r["child"]], r["weight"]) for r in model["relations"]]
        layered = assign_layers(len(names), raw)
        rank = layered["rank"]
        oriented = [((v, u, w) if flip else (u, v, w)) for (u, v, w), flip in zip(raw, layered["reversed"])]
        res = order_layers(list(range(len(names))), dict(enumerate(rank)), oriented)
        self.assertLessEqual(res["crossings"], res["initial_crossings"])
        self.assertEqual(res["crossings"], brute_crossings(res["layers"], links_of(res)))
        self.assertLessEqual(res["crossings"], REAL_CROSSING_BOUND)


REAL_CROSSING_BOUND = 15    # measured on erd_mau_02 (initial order: 79); regression guard


if __name__ == "__main__":
    unittest.main()
