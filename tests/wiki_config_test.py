# tests/wiki_config_test.py — stdlib unittest only (no pytest dependency).
# Run: python3 tests/wiki_config_test.py
import os, sys, tempfile, textwrap, unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
import wiki_config as wc


def _wiki(tmp, schema_text):
    os.makedirs(tmp, exist_ok=True)
    with open(os.path.join(tmp, "schema.md"), "w", encoding="utf-8") as fh:
        fh.write(schema_text)
    return tmp


class TrackConfigTest(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.tmp = self._td.name

    def tearDown(self):
        self._td.cleanup()

    def test_no_declaration_defaults_to_karpathy(self):
        w = _wiki(self.tmp, "---\ntype: reference\n---\n# Schema\n")
        tracks = wc.load_tracks(w)
        self.assertEqual({t["dir"] for t in tracks},
                         {"concepts", "entities", "transcripts"})
        self.assertEqual({t["type"] for t in tracks},
                         {"concept", "entity", "transcript"})

    def test_preset_code_project(self):
        w = _wiki(self.tmp, "---\ntype: reference\npreset: code-project\n---\n")
        dirs = {t["dir"]: t for t in wc.load_tracks(w)}
        self.assertEqual(set(dirs), {"guide", "workflows", "modules"})
        self.assertEqual(dirs["modules"]["requires"], ["module"])

    def test_inline_tracks(self):
        schema = textwrap.dedent("""\
            ---
            type: reference
            tracks:
              - dir: a
                type: alpha
              - dir: b
                type: beta
                requires: [foo]
                path_map: ["pkg/*"]
            ---
            """)
        w = _wiki(self.tmp, schema)
        dirs = {t["dir"]: t for t in wc.load_tracks(w)}
        self.assertEqual(set(dirs), {"a", "b"})
        self.assertEqual(dirs["b"]["requires"], ["foo"])
        self.assertEqual(dirs["b"]["path_map"], ["pkg/*"])

    def test_inline_tracks_terminated_by_top_level_key(self):
        # a top-level frontmatter key after the block must end it cleanly
        schema = textwrap.dedent("""\
            ---
            type: reference
            tracks:
              - dir: a
                type: alpha
            wiki_version: "6.0"
            ---
            """)
        w = _wiki(self.tmp, schema)
        dirs = {t["dir"]: t for t in wc.load_tracks(w)}
        self.assertEqual(set(dirs), {"a"})
        self.assertEqual(dirs["a"]["type"], "alpha")

    def test_preset_and_inline_together_is_error(self):
        schema = ("---\ntype: reference\npreset: code-project\n"
                  "tracks:\n  - dir: a\n    type: alpha\n---\n")
        w = _wiki(self.tmp, schema)
        self.assertRaises(wc.ConfigError, wc.load_tracks, w)

    def test_unknown_preset_is_error(self):
        w = _wiki(self.tmp, "---\ntype: reference\npreset: nope\n---\n")
        self.assertRaises(wc.ConfigError, wc.load_tracks, w)

    def test_preset_name_traversal_is_error(self):
        w = _wiki(self.tmp, "---\ntype: reference\npreset: ../etc/passwd\n---\n")
        self.assertRaises(wc.ConfigError, wc.load_tracks, w)

    def test_inline_duplicate_dir_is_error(self):
        schema = ("---\ntype: reference\ntracks:\n"
                  "  - dir: a\n    type: alpha\n"
                  "  - dir: a\n    type: beta\n---\n")
        w = _wiki(self.tmp, schema)
        self.assertRaises(wc.ConfigError, wc.load_tracks, w)

    def test_inline_invalid_dir_is_error(self):
        schema = "---\ntype: reference\ntracks:\n  - dir: ../evil\n    type: alpha\n---\n"
        w = _wiki(self.tmp, schema)
        self.assertRaises(wc.ConfigError, wc.load_tracks, w)

    def test_extends_and_entrypoints_generic(self):
        # A custom preset that `extends` another and declares extractor/signals
        # entrypoints, exercised with fixture presets (PRESETS_DIR monkeypatched).
        pdir = os.path.join(self.tmp, "presets")
        os.makedirs(pdir, exist_ok=True)
        with open(os.path.join(pdir, "base.json"), "w", encoding="utf-8") as fh:
            fh.write('{"name":"base","tracks":[{"dir":"guide","type":"guide"},'
                     '{"dir":"things","type":"thing"}]}')
        with open(os.path.join(pdir, "child.json"), "w", encoding="utf-8") as fh:
            fh.write('{"name":"child","extends":"base","extractor":"demo",'
                     '"signals":"demo","tracks":[{"dir":"things","type":"thing",'
                     '"path_map":["pkg/*"]}]}')
        orig = wc.PRESETS_DIR
        wc.PRESETS_DIR = pdir
        self.addCleanup(lambda: setattr(wc, "PRESETS_DIR", orig))
        w = _wiki(self.tmp, "---\ntype: reference\npreset: child\n---\n")
        cfg = wc.load_config(w)
        self.assertEqual(cfg["preset"], "child")
        self.assertEqual(cfg["extractor"], "demo")
        self.assertEqual(cfg["signals"], "demo")
        dirs = {t["dir"]: t for t in cfg["tracks"]}
        self.assertEqual(set(dirs), {"guide", "things"})        # inherited + own
        self.assertEqual(dirs["things"]["path_map"], ["pkg/*"])  # child override

    def test_load_config_default_has_no_entrypoints(self):
        w = _wiki(self.tmp, "---\ntype: reference\n---\n")
        cfg = wc.load_config(w)
        self.assertEqual(cfg["preset"], "karpathy")
        self.assertIsNone(cfg["extractor"])
        self.assertIsNone(cfg["signals"])


if __name__ == "__main__":
    unittest.main()
