import copy
import os
import unittest

from diagram_tool.adapters import erd_meta_v1 as A
from diagram_tool.core import jsonio
from diagram_tool.core.errors import ValidationError
from diagram_tool.kinds.raw import to_drawio, validate_raw

REAL_META = r"F:\VScode\MKDC-IoT\Agent\tt02_api\Mau_02_Ban_QL_KKT\document\erd_mau_02.meta.json"


def meta():
    return {
        "schema_version": "1", "version": "2026-11-06", "mau": {"ten_mau": "Mau thu"},
        "tables": [
            {"name": "ban_quan_ly", "kind": "NEW",
             "columns": [{"name": "ma", "pg_type": "varchar(100)", "nullable": False},
                         {"name": "ten", "pg_type": "varchar(250)", "nullable": True},
                         {"name": "cha_id", "pg_type": "uuid", "nullable": True}],
             "primary_key": ["id"], "foreign_keys": [{"columns": ["cha_id"], "ref_table": "ban_quan_ly"}],
             "uniques": [{"name": "UX_ma", "columns": ["ma"], "where": "is_deleted = false"}],
             "indexes": [{"name": "IX_ten", "columns": ["ten", "ma"]}],
             "checks": [{"name": "CK_ma", "expr": "ma <> ''"}]},
            {"name": "bao_cao", "kind": "EXTEND", "other_columns": "unchanged",
             "columns": [{"name": "co_so_id", "pg_type": "uuid", "nullable": True, "change": "ALTER_DROP_NOT_NULL"},
                         {"name": "ban_quan_ly_id", "pg_type": "uuid", "nullable": True, "change": "ADD"},
                         {"name": "ghi_chu", "pg_type": "text"}]},
            {"name": "co_so", "kind": "REUSE"},
            {"name": "khu", "kind": "REUSE", "primary_key": ["id", "ma_khu"]},
            {"name": "dong", "kind": "NEW",
             "columns": [{"name": "id", "pg_type": "uuid"}, {"name": "bao_cao_id", "pg_type": "uuid"},
                         {"name": "bao_cao_nguon_id", "pg_type": "uuid", "nullable": True}]},
        ],
        "relationships": [
            {"parent": "ban_quan_ly", "child": "bao_cao", "fk_column": "ban_quan_ly_id", "parent_card": "0..1",
             "child_card": "0..N", "label": "chu the"},
            {"parent": "co_so", "child": "bao_cao", "fk_column": "co_so_id", "parent_card": "0..1", "child_card": "0..N"},
            {"parent": "ban_quan_ly", "child": "ban_quan_ly", "fk_column": "cha_id", "parent_card": "0..1", "child_card": "0..N"},
            {"parent": "bao_cao", "child": "dong", "fk_column": "bao_cao_id", "parent_card": "1", "child_card": "0..N", "label": "dong"},
            {"parent": "bao_cao", "child": "dong", "fk_column": "bao_cao_nguon_id", "parent_card": "0..1", "child_card": "0..N"},
            {"parent": "co_so", "child": "khu", "fk_column": "co_so_id", "parent_card": "1", "child_card": "0..1"},
            {"parent": "khu", "child": "co_so", "fk_column": "khu_id", "parent_card": "0..1", "child_card": "0..1"},
        ],
    }


def grid(model):
    return {t["name"]: (40 + 500 * i, A.TOP_MARGIN) for i, t in enumerate(model["tables"])}


def table(model, name):
    return {t["name"]: t for t in model["tables"]}[name]


_CHECK = unittest.TestCase()


def err(data, path_part, msg_part=""):
    with _CHECK.assertRaises(ValidationError) as ctx:
        A.parse_erd_meta(data)
    text = str(ctx.exception)
    text.encode("ascii")
    _CHECK.assertIn(path_part, text)
    _CHECK.assertIn(msg_part, text)


class DetectTest(unittest.TestCase):
    def test_is_erd_meta(self):
        self.assertTrue(A.is_erd_meta(meta()))
        self.assertFalse(A.is_erd_meta({"kind": "raw", "tables": [], "relationships": [], "schema_version": "1"}))
        self.assertFalse(A.is_erd_meta({"tables": [], "relationships": [], "schema_version": 1}))
        self.assertFalse(A.is_erd_meta({"tables": []}))
        self.assertFalse(A.is_erd_meta([]))


class RowsTest(unittest.TestCase):
    def setUp(self):
        self.model = A.parse_erd_meta(meta())

    def labels(self, name):
        return [(r["id"], r["role"], r["label"]) for r in table(self.model, name)["rows"]]

    def test_new_table_rows(self):
        self.assertEqual(self.labels("ban_quan_ly"), [
            ("id", "pk", "id uuid PK"),
            ("ma", "plain", "ma varchar(100)"),
            ("ten", "plain", "ten varchar(250) NULL"),
            ("cha_id", "fk", "cha_id uuid NULL"),
            ("uk_ux_ma", "note", "UK UX_ma(ma)"),
            ("ix_ix_ten", "note", "IX IX_ten(ten, ma)"),
            ("ck_ck_ma", "note", "CK CK_ma: ma <> ''"),
        ])

    def test_extend_table_rows(self):
        rows = self.labels("bao_cao")
        self.assertEqual(rows[0], ("id", "pk", "id uuid PK"))
        self.assertEqual(rows[1:3], [("co_so_id", "fk", "co_so_id uuid NULL (ALTER_DROP_NOT_NULL)"),
                                     ("ban_quan_ly_id", "fk", "ban_quan_ly_id uuid NULL (ADD)")])
        self.assertEqual(rows[-1], ("other_columns", "note", "... cac cot khac khong doi"))
        self.assertNotIn("ghi_chu", [r[0] for r in rows])      # unchanged column hidden
        self.assertEqual(len(rows), 4)

    def test_extend_rows_follow_declaration_order(self):
        data = meta()
        data["tables"][1]["columns"] = [
            {"name": "ghi_chu", "pg_type": "text", "change": "ADD"},
            {"name": "co_so_id", "pg_type": "uuid"},                 # FK without change, declared after
            {"name": "bo_qua", "pg_type": "text"}]                   # neither: hidden
        rows = [r["id"] for r in A.parse_erd_meta(data)["tables"][1]["rows"]]
        self.assertEqual(rows[:3], ["id", "ghi_chu", "co_so_id"])
        self.assertNotIn("bo_qua", rows)

    def test_extend_primary_key_shows_change(self):
        data = meta()
        data["tables"][1]["columns"].append({"name": "id", "pg_type": "uuid", "change": "ALTER_TYPE"})
        rows = A.parse_erd_meta(data)["tables"][1]["rows"]
        self.assertEqual(rows[0]["label"], "id uuid (ALTER_TYPE) PK")

    def test_other_columns_row_id_cannot_collide(self):
        data = meta()
        data["tables"][1]["columns"].append({"name": "other_columns", "pg_type": "text", "change": "ADD"})
        ids = [r["id"] for r in A.parse_erd_meta(data)["tables"][1]["rows"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn("other_columns_2", ids)

    def test_reuse_tables_show_pk_and_derived_fk_only(self):
        self.assertEqual(self.labels("co_so"), [("id", "pk", "id uuid PK"), ("khu_id", "fk", "khu_id uuid")])
        self.assertEqual(self.labels("khu"), [("id", "pk", "id uuid PK"), ("ma_khu", "pk", "ma_khu uuid PK"),
                                              ("co_so_id", "fk", "co_so_id uuid")])

    def test_each_column_one_row_and_pk_fk_merge(self):
        rows = self.labels("dong")
        self.assertEqual([r[0] for r in rows], ["id", "bao_cao_id", "bao_cao_nguon_id"])
        self.assertEqual(rows[0], ("id", "pk", "id uuid PK"))        # pk row first; not duplicated from columns
        self.assertEqual(rows[2][1:], ("fk", "bao_cao_nguon_id uuid NULL"))
        data = meta()
        data["tables"][0]["primary_key"] = ["id", "cha_id"]         # PK column that is also FK
        rows = A.parse_erd_meta(data)["tables"][0]["rows"]
        self.assertEqual([r["id"] for r in rows].count("cha_id"), 1)
        pkfk = [r for r in rows if r["id"] == "cha_id"][0]
        self.assertEqual((pkfk["role"], pkfk["label"]), ("pk", "cha_id uuid NULL PK FK"))

    def test_variants_and_titles(self):
        self.assertEqual([(t["name"], t["variant"]) for t in self.model["tables"]],
                         [("ban_quan_ly", "new"), ("bao_cao", "extend"), ("co_so", "reuse"), ("khu", "reuse"), ("dong", "new")])
        self.assertEqual(table(self.model, "bao_cao")["title_label"], "[EXTEND] bao_cao")

    def test_note_rows_are_truncated_and_ids_unique(self):
        data = meta()
        data["tables"][0]["checks"] = [{"name": "CK_" + "x" * 80, "expr": "a"}, {"name": "CK_ma", "expr": "b"},
                                       {"name": "CK_ma", "expr": "c"}]
        rows = A.parse_erd_meta(data)["tables"][0]["rows"]
        long_row = [r for r in rows if r["label"].startswith("CK CK_xxx")][0]
        self.assertEqual(len(long_row["label"]), A.NOTE_LIMIT)
        self.assertTrue(long_row["label"].endswith("..."))
        ids = [r["id"] for r in rows]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn("ck_ck_ma_2", ids)       # collides with the earlier ck_ck_ma note: suffixed

    def test_warning_for_fk_without_relationship(self):
        data = meta()
        data["tables"][4]["foreign_keys"] = [{"columns": ["orphan_id"], "ref_table": "co_so"}]
        model = A.parse_erd_meta(data)
        self.assertEqual(len(model["warnings"]), 1)
        self.assertIn("orphan_id", model["warnings"][0])
        self.assertIn("orphan_id", [r["id"] for r in table(model, "dong")["rows"]])   # still marked FK
        self.assertEqual(A.parse_erd_meta(meta())["warnings"], [])


class RelationTest(unittest.TestCase):
    def setUp(self):
        self.model = A.parse_erd_meta(meta())
        self.rels = {r["id"]: r for r in self.model["relations"]}

    def test_ids_symbols_weights(self):
        self.assertEqual(list(self.rels), ["rel.bao_cao.ban_quan_ly_id", "rel.bao_cao.co_so_id", "rel.ban_quan_ly.cha_id",
                                           "rel.dong.bao_cao_id", "rel.dong.bao_cao_nguon_id", "rel.khu.co_so_id",
                                           "rel.co_so.khu_id"])
        r = self.rels["rel.bao_cao.ban_quan_ly_id"]
        self.assertEqual((r["parent"], r["child"], r["start"], r["end"], r["weight"], r["label"]),
                         ("ban_quan_ly", "bao_cao", "er-zero-one", "er-zero-many", 4, "chu the"))
        self.assertEqual(self.rels["rel.dong.bao_cao_id"]["weight"], 8)          # parent_card "1"
        self.assertEqual(self.rels["rel.dong.bao_cao_id"]["start"], "er-mandatory-one")
        self.assertEqual(self.rels["rel.co_so.khu_id"]["weight"], 1)             # 0..1 : 0..1
        self.assertEqual(self.rels["rel.co_so.khu_id"]["end"], "er-zero-one")
        self.assertEqual(self.rels["rel.khu.co_so_id"]["weight"], 8)             # parent_card "1" wins over child 0..1

    def test_all_cardinality_combinations_have_weight(self):
        for pc in ("1", "0..1", "0..N", "1..N"):
            for cc in ("1", "0..1", "0..N", "1..N"):
                data = meta()
                data["relationships"] = [{"parent": "co_so", "child": "khu", "fk_column": "x", "parent_card": pc, "child_card": cc}]
                r = A.parse_erd_meta(data)["relations"][0]
                self.assertIn(r["weight"], (1, 4, 8))
                self.assertEqual((r["start"], r["end"]), (A.SYMBOL[pc], A.SYMBOL[cc]))

    def test_self_loop_flag_and_duplicate_fk_names(self):
        self.assertTrue(self.rels["rel.ban_quan_ly.cha_id"]["loop"])
        self.assertFalse(self.rels["rel.dong.bao_cao_id"]["loop"])
        data = meta()
        data["relationships"].append(dict(data["relationships"][0]))
        ids = [r["id"] for r in A.parse_erd_meta(data)["relations"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn("rel.bao_cao.ban_quan_ly_id_2", ids)


class WidthTest(unittest.TestCase):
    def test_text_px_groups(self):
        self.assertEqual(A.text_px("iii"), 10.5)
        self.assertEqual(A.text_px("mm"), 20.0)
        self.assertAlmostEqual(A.text_px("abc"), 20.1)
        self.assertAlmostEqual(A.text_px("abc", bold=True), 20.1 * 1.08)
        self.assertAlmostEqual(A.text_px("a = b"), 5 * 6.7)       # '=' and space are NOT narrow (plan 3.4)
        self.assertAlmostEqual(A.text_px("( ) ; : , . f t l j i"), 11 * 3.5 + 10 * 6.7)

    def test_widths_are_multiples_of_40_within_bounds(self):
        model = A.parse_erd_meta(meta())
        for t in model["tables"]:
            self.assertEqual(t["text_width"] % 40, 0)
            self.assertTrue(200 <= t["text_width"] <= 440)
        data = meta()
        data["tables"][0]["columns"].append({"name": "c" * 150, "pg_type": "varchar(250)"})
        t = A.parse_erd_meta(data)["tables"][0]
        self.assertEqual(t["text_width"], 440)
        long_rows = [r for r in t["rows"] if r["id"] == "c" * 150]
        self.assertTrue(long_rows[0]["label"].endswith("..."))
        usable = 440 / A.SAFETY_FACTOR - A.CELL_PADDING
        self.assertLessEqual(A.text_px(long_rows[0]["label"]), usable)


class ErrorsTest(unittest.TestCase):
    def test_errors(self):
        d = meta(); d["schema_version"] = 1
        err(d, "schema_version", "string")
        d = meta(); del d["tables"]
        err(d, "tables", "missing")
        d = meta(); del d["relationships"]
        err(d, "relationships", "missing")
        d = meta(); d["tables"][1]["name"] = "ban_quan_ly"
        err(d, "tables[1].name", "duplicate")
        d = meta(); d["tables"][1]["kind"] = "OLD"
        err(d, "tables[1].kind", "NEW, EXTEND, REUSE")
        d = meta(); d["tables"][0]["name"] = "a b"
        err(d, "tables[0].name", "invalid name")
        d = meta(); d["relationships"][0]["parent"] = "ghost"
        err(d, "relationships[0].parent", "ghost")
        d = meta(); d["relationships"][2]["child"] = 5
        err(d, "relationships[2].child")
        d = meta(); d["relationships"][0]["parent_card"] = "many"
        err(d, "relationships[0].parent_card", "must be one of")
        d = meta(); d["relationships"][0]["fk_column"] = ""
        err(d, "relationships[0].fk_column", "non-empty")
        d = meta(); d["tables"][0]["columns"][0]["name"] = ""
        err(d, "tables[0].columns[0].name")
        d = meta(); d["tables"][0]["primary_key"] = [5]
        err(d, "tables[0].primary_key[0]")
        d = meta(); d["tables"][0]["primary_key"] = []
        err(d, "tables[0].primary_key", "must not be empty")
        d = meta(); d["tables"][0]["primary_key"] = ["a b"]
        err(d, "tables[0].primary_key[0]", "invalid name")
        d = meta(); d["relationships"][0]["fk_column"] = "a:b"
        err(d, "relationships[0].fk_column", "invalid name")
        d = meta(); d["tables"][0]["name"] = "bảng"
        d["relationships"] = []
        A.parse_erd_meta(d)       # non-ASCII names are legal ids; errors stay ASCII
        d["tables"][1]["name"] = "bảng"
        err(d, "tables[1].name", "duplicate")
        err([], "", "expected an object")


class RawDocumentTest(unittest.TestCase):
    def build(self, model=None, routes=None):
        model = model or A.parse_erd_meta(meta())
        return A.build_raw_document(model, grid(model), routes=routes)

    def loop_route(self, model):
        # self-loop on ban_quan_ly: the table is the first one at (40, 100)
        t = table(model, "ban_quan_ly")
        h = 30 + 26 * len(t["rows"])
        w = t["text_width"]
        k1, k2 = 10, 20
        y1, y2 = 100 + h * k1 / 40, 100 + h * k2 / 40
        return {"rel.ban_quan_ly.cha_id": {"exit": {"x": 1, "y": k1 / 40.0}, "entry": {"x": 1, "y": k2 / 40.0},
                                           "points": [{"x": 40 + w + 30, "y": y1}, {"x": 40 + w + 30, "y": y2}]}}, h

    def test_input_schema_shape(self):
        model = A.parse_erd_meta(meta())
        route, h = self.loop_route(model)
        self.assertEqual(h % 2, 0)   # 7 rows -> h = 212; y positions below are 1-decimal numbers
        doc = self.build(model, route)
        cells = doc["pages"][0]["cells"]
        banned = {"h", "loop", "face"}
        for c in cells:
            if c["type"] != "vertex":          # only vertices may carry h
                self.assertFalse(banned & set(c), c["id"])
            self.assertNotIn(None, c.values(), c["id"])
        tables = [c for c in cells if c["type"] == "table"]
        self.assertEqual([c["id"] for c in tables], ["ban_quan_ly", "bao_cao", "co_so", "khu", "dong"])
        self.assertEqual(tables[0]["attrs"], {"entity": "ban_quan_ly", "kind": "NEW"})
        edge = [c for c in cells if c["id"] == "rel.bao_cao.ban_quan_ly_id"][0]
        self.assertEqual(edge["labels"], [{"text": "chu the", "dy": -8}])
        self.assertEqual((edge["source"], edge["target"]), ("ban_quan_ly", "bao_cao"))
        no_label = [c for c in cells if c["id"] == "rel.bao_cao.co_so_id"][0]
        self.assertNotIn("labels", no_label)

    def test_passes_validate_raw_and_emits(self):
        model = A.parse_erd_meta(meta())
        route, _ = self.loop_route(model)
        doc = self.build(model, route)
        result = validate_raw(doc)
        by = {c["id"]: c for c in result.doc["pages"][0]["cells"]}
        self.assertEqual(by["bao_cao"]["h"], 30 + 26 * 4)
        xml, _ = to_drawio(doc)
        self.assertIn("[EXTEND] bao_cao", xml)

    def test_self_loop_without_route_is_refused(self):
        with self.assertRaises(ValueError):
            self.build()

    def test_edge_ids_and_row_ids_survive_validation(self):
        model = A.parse_erd_meta(meta())
        route, _ = self.loop_route(model)
        cells = validate_raw(self.build(model, route)).doc["pages"][0]["cells"]
        for c in cells:
            if c["type"] == "table":
                self.assertEqual([r["id"] for r in c["rows"]], [r["id"] for r in table(model, c["id"])["rows"]])

    def test_deterministic(self):
        route, _ = self.loop_route(A.parse_erd_meta(meta()))
        self.assertEqual(self.build(routes=route), self.build(routes=route))
        self.assertEqual(A.parse_erd_meta(meta()), A.parse_erd_meta(copy.deepcopy(meta())))


@unittest.skipUnless(os.path.exists(REAL_META), "real erd_mau_02.meta.json not available")
class RealDataTest(unittest.TestCase):
    def setUp(self):
        self.data = jsonio.load_file(REAL_META)
        self.model = A.parse_erd_meta(self.data)

    def test_counts_and_kinds(self):
        self.assertTrue(A.is_erd_meta(self.data))
        self.assertEqual(len(self.model["tables"]), 18)
        self.assertEqual(len(self.model["relations"]), 32)
        kinds = [t["kind"] for t in self.model["tables"]]
        self.assertEqual((kinds.count("REUSE"), kinds.count("EXTEND"), kinds.count("NEW")), (7, 2, 9))
        self.assertEqual(self.model["warnings"], [])
        ids = [r["id"] for r in self.model["relations"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn("rel.bao_cao_bql_co_so_kcn.bao_cao_id", ids)
        self.assertIn("rel.bao_cao_bql_co_so_kcn.bao_cao_nguon_id", ids)

    def test_every_row_has_unique_id_and_fits(self):
        for t in self.model["tables"]:
            ids = [r["id"] for r in t["rows"]]
            self.assertEqual(len(ids), len(set(ids)), t["name"])
            self.assertTrue(200 <= t["text_width"] <= 440)
            self.assertEqual(t["rows"][0]["role"], "pk")
            usable = t["text_width"] / A.SAFETY_FACTOR - A.CELL_PADDING
            for r in t["rows"]:
                self.assertLessEqual(A.text_px(r["label"], r["role"] == "pk"), usable + 1e-9, (t["name"], r["id"]))
                self.assertLessEqual(len(r["label"]), 400)

    def test_row_roles_by_kind(self):
        for t in self.model["tables"]:
            roles = {r["role"] for r in t["rows"]}
            if t["kind"] == "REUSE":
                self.assertLessEqual(roles, {"pk", "fk"}, t["name"])
        bc = table(self.model, "bao_cao_moi_truong")
        ids = [r["id"] for r in bc["rows"]]
        self.assertEqual(ids[0], "id")
        for needed in ("co_so_id", "ban_quan_ly_id", "mau_bao_cao_id"):
            self.assertIn(needed, ids)
        self.assertEqual(bc["rows"][0]["label"], "id uuid PK")
        self.assertIn("other_columns", [r["id"] for r in bc["rows"]])
        self.assertTrue(any(r["label"].startswith("IX ") for r in bc["rows"]))
        self.assertEqual(sum(1 for r in bc["rows"] if r["label"].startswith("CK ")), 3)
        co_so_id = [r for r in bc["rows"] if r["id"] == "co_so_id"][0]
        self.assertTrue(co_so_id["label"].endswith("(ALTER_DROP_NOT_NULL)"), co_so_id)

    def test_relation_symbols_on_real_edges(self):
        rel = {r["id"]: r for r in self.model["relations"]}
        r = rel["rel.bao_cao_moi_truong.ban_quan_ly_id"]
        self.assertEqual((r["start"], r["end"]), ("er-zero-one", "er-zero-many"))
        r = rel["rel.mau_bao_cao_section.mau_bao_cao_id"]
        self.assertEqual((r["start"], r["end"], r["weight"]), ("er-mandatory-one", "er-zero-many", 8))
        self.assertEqual(len(rel), 32)

    def test_cycle_edges_present(self):
        pairs = {(r["parent"], r["child"], r["weight"]) for r in self.model["relations"]}
        self.assertIn(("khu_tap_trung", "co_so", 4), pairs)
        self.assertIn(("co_so", "khu_tap_trung", 1), pairs)

    def test_grid_document_validates(self):
        positions = {t["name"]: (40 + 600 * (i % 6), A.TOP_MARGIN + 700 * (i // 6)) for i, t in enumerate(self.model["tables"])}
        doc = A.build_raw_document(self.model, positions)
        validate_raw(doc)


if __name__ == "__main__":
    unittest.main()
