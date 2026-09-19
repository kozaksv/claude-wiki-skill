"""Apply the reviewed safety fixes to one pinned, clean repository snapshot."""
from pathlib import Path
import subprocess
import sys

BASE = "a77aaf18bd64bf03f01817dd4763178ef343bbf0"
assert subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip() == BASE
assert not subprocess.check_output(["git", "status", "--porcelain"], text=True).strip()


def replace(path, before, after):
    target = Path(path)
    text = target.read_text()
    assert text.count(before) == 1, (path, "non-unique patch anchor", before)
    target.write_text(text.replace(before, after), encoding="utf-8")


replace("scripts/wiki.py", 'def headings(text):\n    """ATX headings outside YAML frontmatter and fenced code; 1-based lines."""',
        'def headings(text, *, for_split=False):\n'
        '    """ATX headings and 1-based ranges; destructive splits reject ambiguity."""')
replace("scripts/wiki.py", '        if fence:\n            continue\n        match = re.match(r"^ {0,3}(#{1,6})[ \\t]+(.+?)\\s*$", line)',
        '        if fence:\n            continue\n'
        '        # This scanner is not a full Markdown block parser. A Setext\n'
        '        # underline can end the requested section even though it has no #.\n'
        '        # Refuse ambiguous thematic breaks too; never guess when moving text.\n'
        '        if for_split and re.match(r"^ {0,3}(?:=+|-+)[ \\t]*$", line):\n'
        '            raise WikiError("Possible Setext heading or thematic break; "\n'
        '                            "use the reviewed Split workflow")\n'
        '        match = re.match(r"^ {0,3}(#{1,6})[ \\t]+(.+?)\\s*$", line)')
replace("scripts/wiki.py", 'matches = [h for h in headings(original) if h["level"] == 2 and h["heading"] == heading]',
        'matches = [h for h in headings(original, for_split=True)\n'
        '               if h["level"] == 2 and h["heading"] == heading]')
replace("scripts/wiki.py", '    if re.search(r"\\]\\(|^ {0,3}\\[[^\\]]+\\]:", body, re.MULTILINE):\n'
        '        raise WikiError("Section contains Markdown links; use the reviewed Split workflow to relocate links")',
        '    # Reference definitions may live outside this section. Conservatively\n'
        '    # reject link/HTML markers, including shortcut references and images,\n'
        '    # instead of moving a reference without its definition. Literal markers\n'
        '    # (also in code) and wikilinks go through the reviewed workflow as well.\n'
        '    if re.search(r"[\\[<]|\\]\\(", heading + "\\n" + body):\n'
        '        raise WikiError("Section contains possible links or markup; "\n'
        '                        "use the reviewed Split workflow to relocate links")')

usage_helpers = '''def unique_usage_pairs(pairs):
    # Match the policy reader: duplicate keys can silently erase a true pin.
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate usage key")
        result[key] = value
    return result


def valid_usage(value):
    # Counters are optional, but malformed legacy protection is not an empty DB.
    return isinstance(value, dict) and all(
        name.startswith("_") or (
            isinstance(record, dict) and all(
                field not in record or type(record[field]) is bool
                for field in ("protected", "pinned")))
        for name, record in value.items())


'''
post = Path("hooks/post-tool-use.sh")
text = post.read_text()
start = text.index("# Read the sidecar defensively (codex-атк P1).")
end = text.index('\nnow = time.strftime(', start)
replacement = usage_helpers + '''# Only a genuinely absent sidecar may bootstrap. Existing corrupt, unreadable,
# non-object or invalid legacy protection must stay byte-identical for recovery.
# The read stays inside the directory lock and uses no-follow/non-blocking flags:
# a path changed after the shell gate must not cause a read or overwrite outside
# the wiki, block on a FIFO, or turn unknown protection into an empty database.
data = {}
try:
    fd = os.open(
        usage_path,
        os.O_RDONLY
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_NONBLOCK", 0),
    )
except FileNotFoundError:
    fd = None
except OSError:
    sys.exit(0)
if fd is not None:
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            os.close(fd)
            sys.exit(0)
        with os.fdopen(fd, "r", encoding="utf-8") as f:
            loaded = json.load(f, object_pairs_hook=unique_usage_pairs)
        if not valid_usage(loaded):
            sys.exit(0)
        data = loaded
    except Exception:
        try:
            os.close(fd)
        except Exception:
            pass
        sys.exit(0)
'''
post.write_text(text[:start] + replacement + text[end:], encoding="utf-8")
replace("hooks/post-tool-use.sh", '# Reads {wiki}/.usage.json (corrupt/non-object -> treated as `{}`, per\n'
        '# telemetry.md Tolerance rules), creates the 10-field-default record if the\n'
        '# key is absent.',
        '# Reads {wiki}/.usage.json (corrupt/non-object -> untouched, per\n'
        '# telemetry.md Tolerance rules), creates the 10-field-default record if the\n'
        '# key is absent in a valid object, or the sidecar itself is absent.')

# SessionStart must not normalize duplicate keys or malformed legacy pins before
# PostToolUse gets a chance to preserve them. Both optional writers fail closed.
replace("hooks/session-start.sh", 'def read_usage():\n', usage_helpers + 'def read_usage():\n')
replace("hooks/session-start.sh", '                loaded = json.load(f)\n'
        '            if isinstance(loaded, dict):\n',
        '                loaded = json.load(f, object_pairs_hook=unique_usage_pairs)\n'
        '            if valid_usage(loaded):\n')

replace("tests/hooks/run.sh", '''printf '{not valid json' >"$fixture/docs/wiki/.usage.json"
_ptu_stdin "Read" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
if python3 -c "import json; json.load(open('$fixture/docs/wiki/.usage.json'))" 2>/dev/null; then r=0; else r=1; fi
assert_eq "post-tool-use: corrupt .usage.json recovered to valid JSON" "0" "$r"
vc="$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "view_count")"
assert_eq "post-tool-use: corrupt .usage.json -> fresh record written (view_count 1)" "1" "$vc"''',
        '''printf '{not valid json' >"$fixture/docs/wiki/.usage.json"
sha_before="$(_sha "$fixture/docs/wiki/.usage.json")"
_ptu_stdin "Read" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_file_unchanged "post-tool-use: corrupt .usage.json preserved for legacy-pin recovery" \\
  "$fixture/docs/wiki/.usage.json" "$sha_before"''')
target = Path("tests/hooks/run.sh")
text = target.read_text()
point = text.index("printf '{not valid json'")
comment_start = text.rfind("\n# 6.", 0, point)
fixture_start = text.index('fixture="$(make_fixture)"', comment_start)
assert comment_start >= 0 and fixture_start < point
text = text[:comment_start] + '\n# 6. Corrupt .usage.json stays intact so legacy pins remain recoverable.\n' + text[fixture_start:]
target.write_text(text, encoding="utf-8")

replace(".github/workflows/wiki-contracts.yml", '      - run: bash tests/skill-contracts.sh\n',
        '      - run: bash tests/skill-contracts.sh\n      - run: bash tests/hooks/run.sh\n')
replace("references/wiki-maintenance.md", '''Sections containing Markdown links require the reviewed Split workflow so
relative URLs, heading links and reference definitions are relocated correctly.
It does not synthesize new rules, select a section by size, or rewrite inbound
links automatically. For mixed current/history text, use `operation-split.md`.''',
        '''The automatic helper is deliberately limited to simple, link-free ATX sections.
Possible Setext underlines (`===` / `---`, including ambiguous thematic breaks)
outside YAML frontmatter and fenced code require the reviewed Split workflow;
they are refused before preview or write rather than guessing section boundaries.
Link/HTML markers in the selected heading or body also require review, including
full, collapsed and shortcut references, images and wikilinks. This conservative
guard also refuses literal markers in code; it is not a complete Markdown parser.
The reviewed workflow relocates relative URLs, heading links and reference
definitions using the whole source document. Catalog reading remains available.
The helper does not synthesize new rules, select a section by size, or rewrite
inbound links automatically. For mixed current/history text, use `operation-split.md`.''')

target = Path("tests/test_review_regressions.py")
assert not target.exists()
target.write_bytes(Path(sys.argv[1]).read_bytes())
subprocess.run([sys.executable, "scripts/build_skill.py"], check=True)
print("Applied history safety, legacy-protection guards, regression tests and hook CI.")
