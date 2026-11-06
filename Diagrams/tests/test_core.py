import os
import tempfile
import unittest

from diagram_tool.core import ids, jsonio
from diagram_tool.core.errors import DiagramError, InputError, JsonError, ValidationError
from diagram_tool.core.numfmt import fmt
from diagram_tool.emit.escape import escape_attr


class NumFmtTest(unittest.TestCase):
    def test_cases(self):
        cases = [
            (0, "0"), (0.0, "0"), (-0.0, "0"), (-0.04, "0"), (5, "5"), (-5, "-5"), (5.0, "5"),
            (0.5, "0.5"), (-0.5, "-0.5"), (668.3333, "668.3"), (0.05, "0.1"), (0.04, "0"),
            (1e-9, "0"), (1e20, "100000000000000000000"), (12345678901234567890, "12345678901234567890"),
            (2.25, "2.3"), (2.249, "2.2"), (99.96, "100"), (-1.25, "-1.3"),
        ]
        for value, want in cases:
            self.assertEqual(fmt(value), want, repr(value))

    def test_no_exponent_or_negative_zero(self):
        for value in (1e300, -1e-300, 1.5e-7, -0.0001):
            text = fmt(value)
            self.assertNotIn("e", text.lower())
            self.assertNotEqual(text, "-0")

    def test_rejects(self):
        for bad in (float("nan"), float("inf"), float("-inf")):
            with self.assertRaises(ValueError):
                fmt(bad)
        for bad in (True, False, "1", None):
            with self.assertRaises(TypeError):
                fmt(bad)


class EscapeTest(unittest.TestCase):
    def test_specials(self):
        self.assertEqual(escape_attr('a<b>&"c\''), "a&lt;b&gt;&amp;&quot;c&apos;")
        self.assertEqual(escape_attr("a <=> b"), "a &lt;=&gt; b")
        self.assertEqual(escape_attr("List<Entity>"), "List&lt;Entity&gt;")
        self.assertEqual(escape_attr("a\nb\tc"), "a&#10;b&#9;c")
        self.assertEqual(escape_attr("a\r\nb\rc"), "a&#10;b&#10;c")

    def test_vietnamese_kept(self):
        text = "Báo cáo môi trường đất"
        self.assertEqual(escape_attr(text), text)

    def test_control_chars_rejected(self):
        for bad in ("a\x00b", "a\x01b", "a\x0bb", "a\x1fb", "a\x7fb", "a\x85b", "a\ud800b", "a￾b"):
            with self.assertRaises(ValidationError):
                escape_attr(bad, "p")

    def test_not_string(self):
        with self.assertRaises(ValidationError):
            escape_attr(5)


class IdsTest(unittest.TestCase):
    def test_slug(self):
        self.assertEqual(ids.slug("Ten cơ sở"), "ten_co_so")
        self.assertEqual(ids.slug("Đất đai"), "dat_dai")
        self.assertEqual(ids.slug("id uuid PK"), "id_uuid_pk")
        self.assertEqual(ids.slug("---"), "")

    def test_unique_id(self):
        used = {"a", "a_2"}
        self.assertEqual(ids.unique_id("a", used), "a_3")
        self.assertEqual(ids.unique_id("b", used), "b")
        self.assertEqual(ids.unique_id("b", used), "b_2")

    def test_valid_id(self):
        for good in ("A", "t1", "bang_quan_ly", "cơ"):
            self.assertTrue(ids.is_valid_id(good), good)
        for bad in ("", "a b", "a:b", "a\nb", 5, None, "x" * 201):
            self.assertFalse(ids.is_valid_id(bad), repr(bad))

    def test_composed(self):
        self.assertEqual(ids.cell_id("p1", "A"), "p1:A")
        self.assertEqual(ids.child_id("p1:T", "id"), "p1:T:id")


class JsonIoTest(unittest.TestCase):
    def test_bom_and_plain(self):
        self.assertEqual(jsonio.loads_bytes(b'\xef\xbb\xbf{"a": 1}'), {"a": 1})
        self.assertEqual(jsonio.loads_bytes('{"t": "đ"}'.encode("utf-8")), {"t": "đ"})

    def test_duplicate_key(self):
        with self.assertRaises(JsonError) as ctx:
            jsonio.loads_bytes(b'{"a": 1, "a": 2}')
        self.assertIn("duplicate key", str(ctx.exception))
        with self.assertRaises(JsonError):
            jsonio.loads_bytes(b'{"x": {"a": 1, "b": 2, "a": 3}}')

    def test_nan_inf(self):
        for text in (b'{"a": NaN}', b'{"a": Infinity}', b'{"a": -Infinity}', b'{"a": 1e999}'):
            with self.assertRaises(JsonError):
                jsonio.loads_bytes(text)

    def test_bad_input(self):
        for data in (b"{", b"", b"\xff\xfe\x00", b"[" * 100000):
            with self.assertRaises(JsonError):
                jsonio.loads_bytes(data)

    def test_bool_survives_for_validator(self):
        self.assertIs(jsonio.loads_bytes(b'{"a": true}')["a"], True)

    def test_load_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            good = os.path.join(tmp, "a.json")
            with open(good, "wb") as fh:
                fh.write(b'{"k": [1, 2]}')
            self.assertEqual(jsonio.load_file(good), {"k": [1, 2]})
            with self.assertRaises(InputError) as ctx:
                jsonio.load_file(os.path.join(tmp, "missing.json"))
            self.assertEqual(ctx.exception.exit_code, 2)


class ErrorsTest(unittest.TestCase):
    def test_ascii_and_path(self):
        err = ValidationError("bad đ value", "pages[0].cells[3]")
        text = str(err)
        text.encode("ascii")
        self.assertTrue(text.startswith("pages[0].cells[3]: "))
        self.assertIsInstance(err, DiagramError)
        self.assertEqual(err.exit_code, 1)


if __name__ == "__main__":
    unittest.main()
