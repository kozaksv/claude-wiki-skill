# tests/wiki_autogen_test.py — stdlib unittest only (no pytest dependency).
# Run: python3 tests/wiki_autogen_test.py
#
# Proves the generic, extractor-agnostic autogen core with a FIXTURE extractor
# (no shipped framework extractor): inline tracks + a path_map + an --extractor
# override resolved from a monkeypatched extractors dir.
import os
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "..", "scripts"))
import wiki_autogen as wa  # noqa: E402

# Inline, framework-neutral track config: a "comp" track owning paths under pkg/.
_SCHEMA = textwrap.dedent("""\
    ---
    type: reference
    tracks:
      - dir: comp
        type: unit
        path_map: ["pkg/*"]
    ---
    # Schema
    """)

# A generic fixture extractor: reads the component dir, returns plain facts.
_DEMO_EXTRACTOR = textwrap.dedent("""\
    import os
    def extract_facts(component_dir):
        pys = sorted(f for f in os.listdir(component_dir) if f.endswith('.py'))
        return {"Version": "1.0.0", "Sources": pys}
    """)

_EMPTY_EXTRACTOR = "def extract_facts(component_dir):\n    return {}\n"


def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def _read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


class AutogenGenericTest(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.root = self._td.name
        self.src = os.path.join(self.root, "repo")
        self.wiki = os.path.join(self.root, "wiki")
        _write(os.path.join(self.wiki, "schema.md"), _SCHEMA)
        _write(os.path.join(self.wiki, "index.md"), "# Wiki\n")
        # Fixture extractors dir, monkeypatched in.
        self.ext_dir = Path(os.path.join(self.root, "extractors")).resolve()
        os.makedirs(self.ext_dir, exist_ok=True)
        _write(str(self.ext_dir / "demo.py"), _DEMO_EXTRACTOR)
        _write(str(self.ext_dir / "empty.py"), _EMPTY_EXTRACTOR)
        self._orig_ext = wa._EXTRACTORS_DIR
        wa._EXTRACTORS_DIR = self.ext_dir
        # A component under pkg/ matched by the track path_map.
        _write(os.path.join(self.src, "pkg", "foo", "x.py"), "# x\n")

    def tearDown(self):
        wa._EXTRACTORS_DIR = self._orig_ext
        self._td.cleanup()

    def _run(self, extractor="demo", paths=("pkg/foo/x.py",)):
        return wa.main(["wiki_autogen.py", "--src", self.src, "--wiki", self.wiki,
                        "--extractor", extractor, "--paths"] + list(paths))

    def test_extractor_scaffolds_page_with_facts(self):
        rc = self._run()
        self.assertEqual(rc, 0)
        page = os.path.join(self.wiki, "comp", "foo.md")
        self.assertTrue(os.path.isfile(page), "page should be scaffolded")
        text = _read(page)
        self.assertIn(wa.START_PREFIX, text)
        self.assertIn(wa.END_MARK, text)
        self.assertIn("1.0.0", text)        # extracted fact value
        self.assertIn("x.py", text)         # extractor read the component dir
        self.assertIn("type: unit", text)   # track type
        idx = _read(os.path.join(self.wiki, "index.md"))
        self.assertEqual(idx.count("comp/foo.md"), 1)

    def test_index_pointer_added_only_once(self):
        self._run()
        self._run()
        idx = _read(os.path.join(self.wiki, "index.md"))
        self.assertEqual(idx.count("comp/foo.md"), 1)

    def test_block_replaced_curated_prose_kept(self):
        page = os.path.join(self.wiki, "comp", "foo.md")
        _write(page, textwrap.dedent("""\
            ---
            type: unit
            title: foo
            ---
            # foo

            CURATED PROSE THAT MUST SURVIVE.

            %s
            stale fact
            %s

            # Citations
            """) % (wa.START_MARK, wa.END_MARK))
        self._run()
        text = _read(page)
        self.assertIn("CURATED PROSE THAT MUST SURVIVE.", text)
        self.assertNotIn("stale fact", text)
        self.assertIn("1.0.0", text)
        self.assertEqual(text.count(wa.START_PREFIX), 1)

    def test_empty_facts_is_noop(self):
        before = sorted(os.listdir(self.wiki))
        rc = self._run(extractor="empty")
        self.assertEqual(rc, 0)
        self.assertFalse(os.path.isdir(os.path.join(self.wiki, "comp")))
        self.assertEqual(sorted(os.listdir(self.wiki)), before)

    def test_default_no_extractor_writes_nothing(self):
        # No --extractor and a karpathy-default wiki (no preset extractor) -> no-op.
        _write(os.path.join(self.wiki, "schema.md"),
               "---\ntype: reference\n---\n# Schema\n")
        before = sorted(os.listdir(self.wiki))
        before_idx = _read(os.path.join(self.wiki, "index.md"))
        rc = wa.main(["wiki_autogen.py", "--src", self.src, "--wiki", self.wiki,
                      "--paths", "pkg/foo/x.py"])
        self.assertEqual(rc, 0)
        self.assertFalse(os.path.isdir(os.path.join(self.wiki, "comp")))
        self.assertEqual(sorted(os.listdir(self.wiki)), before)
        self.assertEqual(_read(os.path.join(self.wiki, "index.md")), before_idx)


class ExtractorResolutionSafetyTest(unittest.TestCase):
    def test_unsafe_or_missing_extractor_is_noop(self):
        self.assertIsNone(wa.load_extractor("../../etc/passwd"))
        self.assertIsNone(wa.load_extractor("with/sep"))
        self.assertIsNone(wa.load_extractor("nonexistent_extractor_xyz"))


if __name__ == "__main__":
    unittest.main()
