import json
import os
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

from diagram_tool.core import jsonio
from diagram_tool.core import schema as S
from tests.test_erd_adapter import REAL_META

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # .../Diagrams
EXAMPLES = os.path.join(ROOT, "examples", "raw")
SMOKE_JSON = os.path.join(EXAMPLES, "smoke.json")
SMOKE_DRAWIO = os.path.join(ROOT, "examples", "out", "smoke.drawio")


def run(*args, env_extra=None, input_bytes=None):
    env = dict(os.environ)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    env.pop("PYTHONHASHSEED", None)
    if env_extra:
        env.update(env_extra)
    proc = subprocess.run([sys.executable, "-B", "-m", "diagram_tool"] + list(args), cwd=ROOT, env=env,
                          input=input_bytes, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return proc.returncode, proc.stdout, proc.stderr


def write(path, text):
    with open(path, "wb") as fh:
        fh.write(text.encode("utf-8"))


class CliTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)

    def test_exit_codes(self):
        bad_json = os.path.join(self.tmp, "bad.json")
        write(bad_json, '{"a": 1, "a": 2}')
        dup = run(bad_json, "--stdout")
        self.assertEqual(dup[0], 1)
        self.assertIn(b"duplicate key", dup[2])
        syntax = os.path.join(self.tmp, "syntax.json")
        write(syntax, "{")
        self.assertEqual(run(syntax, "--stdout")[0], 1)
        invalid = os.path.join(self.tmp, "invalid.json")
        write(invalid, json.dumps({"schema_version": 1, "kind": "raw", "pages": [{"id": "p", "cells": [{"id": "A", "type": "vertex"}]}]}))
        code, out, err = run(invalid, "--stdout")
        self.assertEqual((code, out), (1, b""))
        self.assertTrue(err.startswith(b"error: pages[0].cells[0]"))
        nokind = os.path.join(self.tmp, "nokind.json")
        write(nokind, "{}")
        self.assertEqual(run(nokind, "--stdout")[0], 1)
        write(nokind, '{"kind": "erd"}')
        self.assertEqual(run(nokind, "--stdout")[0], 1)
        write(nokind, "[]")
        self.assertEqual(run(nokind, "--stdout")[0], 1)
        self.assertEqual(run(os.path.join(self.tmp, "missing.json"))[0], 2)
        self.assertEqual(run()[0], 2)
        self.assertEqual(run(SMOKE_JSON, "--theme", "neon")[0], 2)
        both = run(SMOKE_JSON, "--stdout", "-o", os.path.join(self.tmp, "x.drawio"))
        self.assertEqual(both[0], 2)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "x.drawio")))
        self.assertEqual(run(SMOKE_JSON, "-o", os.path.join(self.tmp, "no_such_dir", "x.drawio"))[0], 2)

    def test_errors_are_ascii_and_have_no_traceback(self):
        path = os.path.join(self.tmp, "vi.json")
        write(path, json.dumps({"schema_version": 1, "kind": "raw", "pages": [
            {"id": "p", "cells": [{"id": "khối x", "type": "vertex", "x": 0, "y": 0, "w": 1, "h": 1}]}]}))
        code, out, err = run(path, "--stdout")
        self.assertEqual(code, 1)
        err.decode("ascii")
        self.assertNotIn(b"Traceback", err)

    def test_non_string_kind_is_a_clean_error(self):
        path = os.path.join(self.tmp, "kind.json")
        for text in ('{"kind": []}', '{"kind": {}}', '{"kind": 5}', '{"kind": null}', '{"kind": true}'):
            write(path, text)
            code, out, err = run(path, "--stdout")
            self.assertEqual((code, out), (1, b""), text)
            self.assertTrue(err.startswith(b"error: kind"), (text, err))
            self.assertNotIn(b"Traceback", err)

    def test_success_exit_zero_and_warnings_only_on_stderr(self):
        code, out, err = run(SMOKE_JSON, "--stdout")
        self.assertEqual(code, 0)
        self.assertEqual(err.count(b"warning: "), 2)
        err.decode("ascii")
        self.assertTrue(out.startswith(b"<mxfile"))

    def test_stdout_is_utf8_lf_no_bom(self):
        code, out, _ = run(SMOKE_JSON, "--stdout")
        text = out.decode("utf-8")
        self.assertFalse(text.startswith("﻿"))
        self.assertNotIn("\r", text)
        self.assertTrue(text.endswith("</mxfile>\n"))
        self.assertIn("Tiêu đề", text)
        ET.fromstring(out)

    def test_output_file_atomic_and_default_name(self):
        src = os.path.join(self.tmp, "one.json")
        with open(os.path.join(EXAMPLES, "minimal.json"), "rb") as fh:
            data = fh.read()
        with open(src, "wb") as fh:
            fh.write(data)
        code, out, err = run(src)
        self.assertEqual((code, out), (0, b""))
        default = os.path.join(self.tmp, "one.drawio")
        self.assertTrue(os.path.exists(default))
        self.assertEqual(sorted(os.listdir(self.tmp)), ["one.drawio", "one.json"])   # no temp file left
        with open(default, "rb") as fh:
            first = fh.read()
        # overwrite with different content: replaced, not appended
        write(default, "old content")
        explicit = os.path.join(self.tmp, "explicit.drawio")
        write(explicit, "old content")
        self.assertEqual(run(src, "-o", explicit)[0], 0)
        with open(explicit, "rb") as fh:
            self.assertEqual(fh.read(), first)
        self.assertEqual(sorted(os.listdir(self.tmp)), ["explicit.drawio", "one.drawio", "one.json"])
        self.assertEqual(run(src)[0], 0)
        with open(default, "rb") as fh:
            self.assertEqual(fh.read(), first)

    def test_output_may_not_overwrite_the_input(self):
        src = os.path.join(self.tmp, "same.drawio")
        with open(os.path.join(EXAMPLES, "minimal.json"), "rb") as fh:
            data = fh.read()
        with open(src, "wb") as fh:
            fh.write(data)
        self.assertEqual(run(src)[0], 2)                  # default output == input
        self.assertEqual(run(src, "-o", src)[0], 2)
        with open(src, "rb") as fh:
            self.assertEqual(fh.read(), data)

    def test_failed_conversion_does_not_touch_existing_output(self):
        out = os.path.join(self.tmp, "keep.drawio")
        write(out, "keep me")
        bad = os.path.join(self.tmp, "bad.json")
        write(bad, "{")
        self.assertEqual(run(bad, "-o", out)[0], 1)
        with open(out, "rb") as fh:
            self.assertEqual(fh.read(), b"keep me")

    def test_theme_option(self):
        mono = run(SMOKE_JSON, "--stdout")[1]
        accent = run(SMOKE_JSON, "--stdout", "--theme", "accent")[1]
        self.assertNotEqual(mono, accent)
        self.assertIn(b"#1F4E79", accent)
        self.assertNotIn(b"#1F4E79", mono)
        self.assertEqual(run(SMOKE_JSON, "--stdout", "--theme", "mono")[1], mono)

    def test_deterministic_across_hash_seeds(self):
        outputs = {run(SMOKE_JSON, "--stdout", env_extra={"PYTHONHASHSEED": seed})[1] for seed in ("0", "1", "424242", "random")}
        self.assertEqual(len(outputs), 1)

    def test_no_pycache_created(self):
        run(SMOKE_JSON, "--stdout")
        for dirpath, dirnames, _ in os.walk(ROOT):
            self.assertNotIn("__pycache__", dirnames, dirpath)

    def test_examples_convert(self):
        for name in sorted(os.listdir(EXAMPLES)):
            if name.endswith(".json"):
                code, out, err = run(os.path.join(EXAMPLES, name), "--stdout")
                self.assertEqual(code, 0, (name, err))
                ET.fromstring(out)


ERD_DEMO = os.path.join(ROOT, "examples", "erd", "erd_demo.meta.json")
ERD_GOLDEN = os.path.join(ROOT, "examples", "out", "erd_demo.gen.drawio")


class ErdCliTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)
        with open(ERD_DEMO, "rb") as fh:
            self.demo_bytes = fh.read()

    def copy_demo(self, name="x.meta.json"):
        path = os.path.join(self.tmp, name)
        with open(path, "wb") as fh:
            fh.write(self.demo_bytes)
        return path

    def test_detected_by_structure(self):
        code, out, err = run(ERD_DEMO, "--stdout")
        self.assertEqual(code, 0, err)
        root = ET.fromstring(out)
        self.assertEqual(len(root.findall("diagram")), 1)
        self.assertIn(b"[NEW] khu", out)
        self.assertIn(b"[EXTEND] bao_cao", out)
        self.assertIn(b"[REUSE] co_quan", out)

    def test_default_name_drops_meta_and_adds_gen(self):
        src = self.copy_demo("erd_x.meta.json")
        code, out, err = run(src)
        self.assertEqual((code, out), (0, b""))
        self.assertEqual(sorted(os.listdir(self.tmp)), ["erd_x.gen.drawio", "erd_x.meta.json"])
        self.assertTrue(err.startswith(b"wrote: "), err)
        plain = self.copy_demo("plain.json")
        run(plain)
        self.assertIn("plain.gen.drawio", os.listdir(self.tmp))      # erd kind always gets .gen.drawio

    def test_kind_option(self):
        self.assertEqual(run(ERD_DEMO, "--stdout", "--kind", "erd")[0], 0)
        code, out, err = run(ERD_DEMO, "--stdout", "--kind", "raw")
        self.assertEqual((code, out), (1, b""))
        self.assertIn(b"kind", err)
        code, out, err = run(SMOKE_JSON, "--stdout", "--kind", "erd")
        self.assertEqual((code, out), (1, b""))
        self.assertEqual(run(SMOKE_JSON, "--stdout", "--kind", "raw")[0], 0)
        self.assertEqual(run(ERD_DEMO, "--kind", "bogus")[0], 2)

    def test_output_directory(self):
        src = self.copy_demo()
        outdir = os.path.join(self.tmp, "out")
        os.mkdir(outdir)
        code, _, err = run(src, "-o", outdir)
        self.assertEqual(code, 0, err)
        self.assertEqual(os.listdir(outdir), ["x.gen.drawio"])
        # a path that does not exist is a FILE name (parent must exist)
        target = os.path.join(self.tmp, "named.drawio")
        self.assertEqual(run(src, "-o", target)[0], 0)
        self.assertTrue(os.path.isfile(target))
        self.assertEqual(run(src, "-o", os.path.join(self.tmp, "missing", "f.drawio"))[0], 2)

    def test_trailing_separator_means_directory_that_must_exist(self):
        src = self.copy_demo()
        code, out, err = run(src, "-o", os.path.join(self.tmp, "newdir") + os.sep)
        self.assertEqual(code, 2)
        self.assertIn(b"does not exist", err)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "newdir")))

    def test_meta_suffix_is_dropped_case_insensitively(self):
        src = self.copy_demo("Big.META.json")
        run(src)
        self.assertIn("Big.gen.drawio", os.listdir(self.tmp))

    def test_wrote_line_names_the_output_path(self):
        src = self.copy_demo()
        code, _, err = run(src)
        self.assertEqual(err.decode("ascii").strip(), "wrote: " + os.path.join(self.tmp, "x.gen.drawio"))

    def test_no_clobber_with_output_directory_and_raw_kind(self):
        outdir = os.path.join(self.tmp, "o")
        os.mkdir(outdir)
        self.assertEqual(run(ERD_DEMO, "-o", outdir)[0], 0)
        first = os.path.join(outdir, "erd_demo.gen.drawio")
        write(first, "keep")
        code, _, err = run(ERD_DEMO, "-o", outdir, "--no-clobber")
        self.assertEqual(code, 0)
        self.assertTrue(err.startswith(b"skipped: "))
        with open(first, "rb") as fh:
            self.assertEqual(fh.read(), b"keep")
        self.assertEqual(run(SMOKE_JSON, "-o", outdir)[0], 0)           # raw: <name>.drawio inside the directory
        self.assertTrue(os.path.isfile(os.path.join(outdir, "smoke.drawio")))

    def test_no_clobber(self):
        src = self.copy_demo()
        out = os.path.join(self.tmp, "x.gen.drawio")
        write(out, "precious")
        code, _, err = run(src, "--no-clobber")
        self.assertEqual(code, 0)
        self.assertTrue(err.startswith(b"skipped: "), err)
        with open(out, "rb") as fh:
            self.assertEqual(fh.read(), b"precious")
        code, _, err = run(src)                      # without the flag the file is replaced
        self.assertTrue(err.startswith(b"wrote: "), err)
        with open(out, "rb") as fh:
            self.assertTrue(fh.read().startswith(b"<mxfile"))

    def test_errors_are_clean_and_ascii(self):
        bad = json.loads(self.demo_bytes.decode("utf-8"))
        bad["relationships"][0]["parent"] = "ghost"
        path = os.path.join(self.tmp, "bad.meta.json")
        write(path, json.dumps(bad))
        code, out, err = run(path, "--stdout")
        self.assertEqual((code, out), (1, b""))
        self.assertTrue(err.startswith(b"error: relationships[0].parent"), err)
        err.decode("ascii")
        self.assertNotIn(b"Traceback", err)

    def test_warnings_go_to_stderr_in_ascii(self):
        data = json.loads(self.demo_bytes.decode("utf-8"))
        data["tables"][2]["foreign_keys"].append({"columns": ["m\u1ed3_c\u00f4i_id"], "ref_table": "co_quan"})
        path = os.path.join(self.tmp, "w.meta.json")
        write(path, json.dumps(data))
        code, out, err = run(path, "--stdout")
        self.assertEqual(code, 0)
        self.assertIn(b"warning: ", err)
        err.decode("ascii")

    def test_golden_file_matches_a_fresh_run(self):
        code, fresh, _ = run(ERD_DEMO, "--stdout")
        self.assertEqual(code, 0)
        with open(ERD_GOLDEN, "rb") as fh:
            self.assertEqual(fh.read(), fresh)

    def test_deterministic_across_hash_seeds(self):
        outputs = {run(ERD_DEMO, "--stdout", env_extra={"PYTHONHASHSEED": s})[1] for s in ("0", "1", "424242", "random")}
        self.assertEqual(len(outputs), 1)

    def test_demo_covers_the_features(self):
        data = jsonio.load_file(ERD_DEMO)
        kinds = {t["kind"] for t in data["tables"]}
        self.assertEqual(kinds, {"NEW", "EXTEND", "REUSE"})
        rels = data["relationships"]
        self.assertTrue(any(r["parent"] == r["child"] for r in rels))                       # self-loop
        pairs = {(r["parent"], r["child"]) for r in rels}
        self.assertTrue(any((b, a) in pairs for a, b in pairs if a != b))                    # cycle
        counts = {}
        for r in rels:
            counts[(r["parent"], r["child"])] = counts.get((r["parent"], r["child"]), 0) + 1
        self.assertTrue(any(c > 1 for c in counts.values()))                                 # parallel FKs

    @unittest.skipUnless(os.path.exists(REAL_META), "real meta not available")
    def test_real_meta_through_the_cli(self):
        code, out, err = run(REAL_META, "--stdout", "--kind", "erd")
        self.assertEqual(code, 0, err)
        self.assertEqual(err, b"")
        ET.fromstring(out)


class SmokeTest(unittest.TestCase):
    def test_committed_smoke_drawio_matches_a_fresh_run(self):
        code, fresh, _ = run(SMOKE_JSON, "--stdout")
        self.assertEqual(code, 0)
        with open(SMOKE_DRAWIO, "rb") as fh:
            self.assertEqual(fh.read(), fresh)

    def test_smoke_covers_the_features_the_plan_lists(self):
        doc = jsonio.load_file(SMOKE_JSON)
        cells = [c for p in doc["pages"] for c in p["cells"]]
        self.assertEqual(len(doc["pages"]), 2)
        used = set()
        for c in cells:
            if c["type"] == "edge":
                used.update((c.get("start", "none"), c.get("end", "classic")))
        self.assertTrue(set(S.ARROW_SYMBOLS) <= used, set(S.ARROW_SYMBOLS) - used)
        tables = [c for c in cells if c["type"] == "table"]
        self.assertEqual(sorted(len(t["rows"]) for t in tables), [1, 2, 5, 20])
        self.assertEqual({t.get("variant") for t in tables}, {"new", "extend", "reuse", None})
        self.assertEqual({r.get("role", "plain") for t in tables for r in t["rows"] if isinstance(r, dict)},
                         set(S.ROW_ROLES))
        edges = [c for c in cells if c["type"] == "edge"]
        self.assertEqual({len(e.get("points", [])) for e in edges}, {0, 1, 2, 3, 4})
        faces = set()
        for e in edges:
            for key in ("exit", "entry"):
                if key in e:
                    p = e[key]
                    faces.add("left" if p["x"] == 0 else "right" if p["x"] == 1 else "top" if p["y"] == 0 else "bottom")
        self.assertEqual(faces, {"left", "right", "top", "bottom"})
        parents = {c["id"]: c.get("parent") for c in cells}
        self.assertTrue(any(parents.get(parents.get(i)) for i in parents if parents.get(i)))   # nested two levels
        # edges whose (derived) parent is a container, checked on the validated document
        from diagram_tool.kinds.raw import validate_raw
        norm = validate_raw(doc).doc["pages"][0]["cells"]
        containers = {c["id"] for c in norm if c["type"] == "vertex" and c["role"] == "container"}
        edge_parents = {c["id"]: c["parent"] for c in norm if c["type"] == "edge"}
        self.assertTrue(any(p in containers for p in edge_parents.values()))
        self.assertEqual(edge_parents["EIn2"], "C2")
        self.assertEqual(edge_parents["ECross"], "C")
        self.assertTrue(any(e["source"] == e["target"] for e in edges))
        self.assertTrue(any(c.get("role") == "note" for c in cells))
        labels = " ".join(c.get("label", "") for c in cells)
        self.assertIn("<=>", labels)
        self.assertIn("\n", labels)
        self.assertTrue(any(ord(ch) > 127 for ch in labels))
        self.assertTrue(any(len(e.get("labels", [])) >= 2 for e in edges))
        self.assertTrue(any("style_raw" in c for c in cells))
        self.assertTrue(any("attrs" in c for c in cells))


if __name__ == "__main__":
    unittest.main()
