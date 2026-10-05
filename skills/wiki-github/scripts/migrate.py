#!/usr/bin/env python3
"""Release-B instruction consolidation helper: plan, check, apply, commit, rollback, private.

Deterministic and LLM-free. The agent reviews/edits the proposed outputs and
coverage decisions stored in the local plan JSON; this helper validates and
applies only an approved, unchanged plan. Plans, state and backups live under
the worktree's Git metadata directory (`wiki-migration/<id>/`), never in the
public tree.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
_SPEC = importlib.util.spec_from_file_location("wiki_instructions", ROOT / "scripts/instructions.py")
AUDIT = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(AUDIT)

SCHEMA = 1
LEGACY = ("CLAUDE.md", ".claude/CLAUDE.md", "GEMINI.md", "QWEN.md")
CANONICAL = "AGENTS.md"
PRIVATE = "CLAUDE.local.md"
OBSERVED = ("AGENTS.override.md", ".claude/AGENTS.md", ".qwen/QWEN.local.md")
AGY_FILE_BUDGET = 24000
CODEX_CHAIN_DEFAULT = 32 * 1024
HARNESS_WORDS = re.compile(r"\b(claude|gemini|qwen|codex|agy|antigravity|agents?)(\.md)?\b", re.I)
POINTER_HEADING = re.compile(r"^##\s+(wiki|вікі)([\s\W]|$)", re.I)
HEADING = re.compile(r"^(#{1,3})\s+\S")
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
CRITICAL = re.compile(r"\b(must|never|do not|don't|always|forbidden|required)\b|заборон|обов['’ʼ]?язков|ніколи|не можна|завжди", re.I)
CLAUDE_IMPORT = re.compile(r"(^|\s)@(?!\[)(?!\S+@)([~./\w-][^\s]*)")
AGY_INCLUDE = re.compile(r"@\[[^\]]*\]\([^)]+\)")
AGY_TRIGGERS = {"always_on", "model_decision", "glob", "manual"}
TEMPLATE_LINES = [re.compile(p) for p in (
    r"^Wiki schema and operations → `[^`]+`\.( Skill: `wiki`\.)?$",
    r"^Wiki at `[^`]+`\.( Schema → `[^`]+`\.)?( Skill: `wiki`\.)?$",
    r"^\*\*ОБОВ'ЯЗКОВО на старті сесії:\*\* прочитай `[^`]+` ДО$",
    r"^будь-якої project-specific відповіді \(як налаштувати X / де лежить Y / як працює Z /$",
    r"^«пам'ятаєш як ми\.\.\.»\)\. Кожна така відповідь МАЄ містити `\[\[page-name\]\]` цитати на$",
    r"^сторінки вікі\. Без цитат — баг, переробити\. Memory-first заборонено: якщо вікі$",
    r"^суперечить пам'яті — вікі виграє\.$",
    r"^Для пошуку викликай скіл `wiki` \(operation: query\)\.$",
    r"^Read the complete `[^`]+` and relevant wiki$",
    r"^pages before a project-specific answer\. Cite the pages actually read\. Memory$",
    r"^and injected markers do not replace source reads\. Use the `wiki` skill to query\.$",
)]


class MigrationError(Exception):
    pass


# ---------------------------------------------------------------- utilities

def sha(data: bytes | str) -> str:
    return hashlib.sha256(data.encode("utf-8") if isinstance(data, str) else data).hexdigest()


def git(root: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    env = dict(os.environ, GIT_OPTIONAL_LOCKS="0", GIT_TERMINAL_PROMPT="0")
    proc = subprocess.run(["git", "-C", str(root), *args], env=env, capture_output=True, text=True, timeout=30)
    if check and proc.returncode:
        raise MigrationError(f"git {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc


def norm_apostrophe(text: str) -> str:
    return text.replace("’", "'").replace("ʼ", "'")


def norm_block(text: str) -> str:
    lines = [norm_apostrophe(line.rstrip()) for line in text.splitlines()]
    while lines and not lines[0]: lines.pop(0)
    while lines and not lines[-1]: lines.pop()
    return "\n".join(lines)


def norm_space(text: str) -> str:
    return " ".join(norm_apostrophe(text).split())


def file_state(path: Path) -> dict[str, Any]:
    kind = AUDIT.kind(path)
    state: dict[str, Any] = {"kind": kind}
    if kind == "file": state["sha256"] = sha(path.read_bytes())
    if kind == "symlink": state["link_target"] = os.readlink(path)
    return state


def migration_dir(root: Path, plan_id: str, create: bool = False) -> Path:
    gitdir = Path(git(root, "rev-parse", "--absolute-git-dir").stdout.strip())
    path = gitdir / "wiki-migration" / plan_id
    if create:
        path.mkdir(parents=True, exist_ok=True)
        os.chmod(path.parent, 0o700); os.chmod(path, 0o700)
    return path


def write_private(path: Path, data: bytes | str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(data.encode("utf-8") if isinstance(data, str) else data)
    os.chmod(path, 0o600)


def atomic_replace(path: Path, content: str) -> None:
    """Replace the directory entry itself; a symlink is replaced, never written through."""
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = 0o644
    if AUDIT.kind(path) == "file": mode = stat.S_IMODE(path.stat().st_mode)
    fd, tmp = tempfile.mkstemp(prefix=".wiki-migrate-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream: stream.write(content.encode("utf-8"))
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        if os.path.lexists(tmp): os.unlink(tmp)
        raise


def tracked_clean(root: Path, rel: str) -> tuple[bool, bool]:
    tracked = git(root, "ls-files", "--error-unmatch", "--", rel, check=False).returncode == 0
    dirty = bool(git(root, "status", "--porcelain", "--untracked-files=all", "--", rel).stdout.strip())
    return tracked, tracked and not dirty


def head_commit(root: Path) -> str | None:
    proc = git(root, "rev-parse", "--verify", "-q", "HEAD^{commit}", check=False)
    return proc.stdout.strip() or None


# ---------------------------------------------------------------- fragments

def fragments(rel: str, text: str, scope: str) -> list[dict[str, Any]]:
    """Fence-aware split covering every non-blank line exactly once."""
    lines = text.splitlines(keepends=True)
    out: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    fence = ""
    index = 0

    def start(kind: str, line_no: int, heading: str = "") -> dict[str, Any]:
        return {"kind": kind, "start": line_no, "end": line_no, "heading": heading, "lines": []}

    def close() -> None:
        nonlocal current
        if current and "".join(current["lines"]).strip():
            body = "".join(current["lines"])
            out.append({"id": f"{rel}#{len(out) + 1}", "source": rel, "scope": scope,
                        "kind": current["kind"], "start": current["start"], "end": current["end"],
                        "heading": current["heading"], "text": body, "sha256": sha(norm_block(body))})
        current = None

    if lines and lines[0].strip() == "---":
        end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
        if end is not None:
            current = start("frontmatter", 1)
            current["lines"] = lines[:end + 1]; current["end"] = end + 1
            close(); index = end + 1
    for number in range(index, len(lines)):
        line = lines[number]
        plain = line.rstrip("\n")
        fence_match = FENCE.match(plain)
        if fence_match:
            marker = fence_match.group(1)
            if not fence: fence = marker
            elif marker[0] == fence[0] and len(marker) >= len(fence) and not plain.strip()[len(marker):].strip():
                fence = ""
        elif not fence:
            heading = HEADING.match(plain)
            if heading:
                level = len(heading.group(1))
                if level == 1 and not any(f["kind"] == "h1" for f in out) and (current is None or current["kind"] == "preamble" and not "".join(current["lines"]).strip()):
                    close(); current = start("h1", number + 1, plain.strip())
                    current["lines"].append(line); close(); continue
                if level >= 2 or (level == 1):
                    close()
                    kind = "pointer" if POINTER_HEADING.match(plain.strip()) else "section"
                    current = start(kind, number + 1, plain.strip())
        if current is None: current = start("preamble", number + 1)
        current["lines"].append(line); current["end"] = number + 1
    close()
    for fragment in out:
        fragment["critical"] = [norm_space(l) for l in fragment["text"].splitlines()
                                if CRITICAL.search(l) and not is_template(l)]
    return out


def is_template(line: str) -> bool:
    plain = norm_apostrophe(line.strip())
    return any(p.match(plain) for p in TEMPLATE_LINES)


def pointer_target(fragment_text: str) -> str | None:
    for line in fragment_text.splitlines()[1:]:
        match = re.search(r"`([^`]+)`", line)
        if match: return match.group(1)
    return None


def pointer_is_template(fragment: dict[str, Any]) -> bool:
    body = fragment["text"].splitlines()[1:]
    return all(not line.strip() or is_template(line) for line in body)


def h1_key(text: str) -> str:
    return norm_space(HARNESS_WORDS.sub(" ", text.lstrip("#").replace("—", " ").replace("-", " "))).lower()


def wiki_block(dest_dir: Path, wiki: Path) -> str:
    rel = Path(os.path.relpath(wiki, dest_dir)).as_posix()
    return ("## Wiki\n\n"
            f"Wiki at `{rel}`. Schema → `{rel}/schema.md`. Skill: `wiki`.\n\n"
            f"Read the complete `{rel}/index.md` and relevant wiki\n"
            "pages before a project-specific answer. Cite the pages actually read. Memory\n"
            "and injected markers do not replace source reads. Use the `wiki` skill to query.\n")


# ---------------------------------------------------------------- plan

def join(scope: str, name: str) -> str:
    return name if scope in (".", "") else f"{scope}/{name}"


def scope_of(rel: str) -> str:
    parent = Path(rel).parent
    if parent.name == ".claude": parent = parent.parent
    return parent.as_posix()


def selection(cwd: Path) -> dict[str, Any]:
    return AUDIT.discovery(cwd)


def rel_or_none(path: str | None, root: Path) -> str | None:
    if not path: return None
    return Path(os.path.relpath(Path(path).resolve(), root)).as_posix()


def build_plan(project: Path) -> dict[str, Any]:
    project = project.resolve()
    top = git(project, "rev-parse", "--show-toplevel").stdout.strip()
    root = Path(top).resolve()
    entries, inventory_warnings = AUDIT.inventory(root)
    plan: dict[str, Any] = {"schema_version": SCHEMA, "id": time.strftime("%Y%m%d-%H%M%S-") + os.urandom(3).hex(),
                            "root": str(root), "base": {"commit": head_commit(root)},
                            "sources": [], "fragments": [], "outputs": [], "deletes": [], "coverage": [],
                            "private": [], "findings": [], "decisions": {"includes_approved": False},
                            "optimization": {"step": "lint-11", "skipped": None}, "initial": {}, "target": {}}
    findings = plan["findings"]
    for warning in inventory_warnings: findings.append({"level": "blocked", "code": "inventory_incomplete", "detail": warning})
    by_scope: dict[str, dict[str, dict[str, Any]]] = {}
    for entry in entries:
        rel = entry["path"]; name = Path(rel).name
        if not entry["exact_case"]:
            findings.append({"level": "blocked", "code": "case_variant", "path": rel,
                             "detail": "rename explicitly to exact-case AGENTS.md before consolidation"})
            continue
        if rel.endswith(PRIVATE):
            plan["private"].append({"source": rel, "scope": scope_of(rel), "tracked": entry["tracked"]})
            findings.append({"level": "warning", "code": "claude_private_blocker", "path": rel,
                             "detail": "Claude reads CLAUDE.md files instead of AGENTS.md while this exists; use `migrate.py private`"})
            continue
        if any(rel == o or rel.endswith("/" + o) for o in OBSERVED):
            findings.append({"level": "warning", "code": "native_file_untouched", "path": rel})
            continue
        if name not in ("AGENTS.md", "CLAUDE.md", "GEMINI.md", "QWEN.md"): continue
        if rel.endswith(".claude/AGENTS.md"): continue
        by_scope.setdefault(scope_of(rel), {})[rel] = entry
    cwds = sorted(set(by_scope) | {"."})
    for cwd in cwds:
        found = selection(root / cwd)
        if found["same_level_conflict"]:
            findings.append({"level": "blocked", "code": "same_level_wiki_conflict", "path": cwd,
                             "detail": "resolve different valid wiki pointers on one level first"})
        plan["initial"][cwd] = rel_or_none(found["selected"], root)
    plan["target"] = dict(plan["initial"])
    plan["cwds"] = cwds
    for scope in sorted(by_scope):
        plan_scope(plan, root, scope, by_scope[scope])
    plan["inbound_refs"] = inbound_refs(root, [d["path"] for d in plan["deletes"]])
    plan["status"] = plan_status(plan)
    return plan


def plan_scope(plan: dict[str, Any], root: Path, scope: str, files: dict[str, dict[str, Any]]) -> None:
    base = root / scope
    canonical_rel = join(scope, CANONICAL)
    legacy_rels = [join(scope, n) for n in LEGACY]
    legacy_rels = [r for r in legacy_rels if r in files]
    if not legacy_rels:
        return
    findings = plan["findings"]
    canonical = files.get(canonical_rel)
    physical: dict[str, str] = {}
    for rel in [canonical_rel, *legacy_rels]:
        if rel not in files: continue
        path = root / rel
        real = path.resolve()
        if not AUDIT.inside(real, root):
            findings.append({"level": "blocked", "code": "symlink_escape", "path": rel}); return
        if AUDIT.kind(path) == "symlink" and real.as_posix() not in {(root / r).resolve().as_posix() for r in files if AUDIT.kind(root / r) == "file"}:
            findings.append({"level": "blocked", "code": "unknown_alias", "path": rel, "detail": os.readlink(path)}); return
        physical[rel] = real.as_posix()
        plan["sources"].append({"path": rel, **file_state(path), "tracked": files[rel]["tracked"], "scope": scope})
    canonical_kind = AUDIT.kind(root / canonical_rel)
    canonical_text = ""
    materialize = False
    if canonical_kind == "file":
        canonical_text = (root / canonical_rel).read_text(encoding="utf-8")
    elif canonical_kind == "symlink":
        canonical_text = (root / canonical_rel).read_text(encoding="utf-8")
        materialize = True
    # A materialized alias is covered via its target; its text still feeds dedupe.
    canonical_frags = fragments(canonical_rel, canonical_text, scope) if canonical_text else []
    for f in canonical_frags: f["class"] = "canonical"
    if canonical_kind == "file": plan["fragments"].extend(canonical_frags)
    draft = canonical_text
    seen = {f["sha256"]: f["id"] for f in canonical_frags}
    headings = {norm_space(f["heading"]).lower(): f["id"] for f in canonical_frags if f["heading"] and f["kind"] in ("section", "pointer")}
    draft_h1 = next((f for f in canonical_frags if f["kind"] == "h1"), None)
    pointer_needed = False
    wiki_for_scope = plan["initial"].get(scope)
    canonical_pointer_ok = any(f["kind"] == "pointer" and pointer_resolves(f, root / scope, root, wiki_for_scope) for f in canonical_frags)
    canonical_real = physical.get(canonical_rel)
    for rel in legacy_rels:
        path = root / rel
        is_alias_of_canonical = canonical_real is not None and physical.get(rel) == canonical_real
        if AUDIT.kind(path) == "symlink":
            if not is_alias_of_canonical:
                findings.append({"level": "blocked", "code": "unknown_alias", "path": rel, "detail": os.readlink(path)}); return
            plan["deletes"].append({"path": rel, "kind": "symlink", "link_target": os.readlink(path), "reason": "alias of canonical"})
            continue
        text = path.read_text(encoding="utf-8")
        frags = fragments(rel, text, scope)
        plan["fragments"].extend(frags)
        if materialize and is_alias_of_canonical:
            for f in frags:
                f["class"] = "identical"
                plan["coverage"].append({"fragment": f["id"], "disposition": "duplicate", "destination": canonical_rel,
                                         "note": "canonical symlink materialized from this file", "approved": True})
            plan["deletes"].append({"path": rel, **file_state(path), "after": canonical_rel, "reason": "target of materialized canonical alias"})
            continue
        stub = all(f["kind"] in ("h1", "pointer") for f in frags) and any(f["kind"] == "pointer" for f in frags) \
            and all(pointer_is_template(f) for f in frags if f["kind"] == "pointer")
        whole_identical = canonical_kind == "file" and norm_block(strip_h1(text)) == norm_block(strip_h1(canonical_text))
        for f in frags:
            entry = {"fragment": f["id"], "destination": canonical_rel, "approved": True}
            if f["kind"] == "pointer":
                pointer_ok = pointer_resolves(f, path.parent, root, wiki_for_scope)
                template = pointer_is_template(f)
                f["class"] = "generated-pointer-stub" if stub else ("contained-exact" if f["sha256"] in seen else "pointer")
                if not template:
                    custom = "\n".join(l for l in f["text"].splitlines()[1:] if l.strip() and not is_template(l))
                    f["class"] = "unique"
                    entry.update(disposition="placed", approved=False, note="pointer section carries custom text; keep it in canonical")
                    draft = append_block(draft, f"{custom}\n")
                    f["placed_text"] = custom
                else:
                    entry.update(disposition="pointer", note="regenerated as canonical Wiki block" if not canonical_pointer_ok else "canonical pointer already valid")
                if not canonical_pointer_ok and wiki_for_scope:
                    pointer_needed = True
                if not pointer_ok:
                    plan["findings"].append({"level": "warning", "code": "stale_legacy_pointer", "path": rel})
            elif stub:
                f["class"] = "generated-pointer-stub"; entry.update(disposition="stub")
            elif redirect_targets(f, path.parent, root) and redirect_targets(f, path.parent, root) <= set(files):
                f["class"] = "contained-exact"
                entry.update(disposition="duplicate", note="import redirect to a consolidated instruction file")
            elif whole_identical or f["sha256"] in seen:
                f["class"] = "identical" if whole_identical else "contained-exact"
                entry.update(disposition="duplicate", duplicate_of=seen.get(f["sha256"], canonical_rel))
            elif f["kind"] == "h1":
                if draft_h1 is None:
                    f["class"] = "unique"; draft_h1 = f
                    draft = f["text"] + ("\n" if draft and not draft.startswith("\n") else "") + draft
                    entry.update(disposition="placed")
                elif h1_key(f["heading"]) == h1_key(draft_h1["heading"]):
                    f["class"] = "contained-exact"; entry.update(disposition="duplicate", duplicate_of=draft_h1["id"], note="H1 differs only by harness name")
                else:
                    f["class"] = "unique"; entry.update(disposition="dropped", approved=False, note="second H1; keep canonical title or edit")
            elif f["kind"] == "frontmatter":
                f["class"] = "unique"; entry.update(disposition="dropped", approved=False, note="frontmatter cannot be appended mid-file")
            else:
                key = norm_space(f["heading"]).lower()
                f["class"] = "conflict-or-unknown" if key and key in headings else "unique"
                entry.update(disposition="placed", approved=False)
                if f["class"] == "conflict-or-unknown": entry["conflict_with"] = headings[key]
                kept = [l for l in f["text"].splitlines(keepends=True)
                        if not (IMPORT_LINE.match(l.rstrip("\n")) and
                                redirect_targets({"kind": "section", "text": l}, path.parent, root) <= set(files))]
                if len(kept) != len(f["text"].splitlines(keepends=True)):
                    f["placed_text"] = "".join(kept)
                    entry["note"] = "import of a consolidated file removed from draft; review the surrounding redirect prose"
                draft = append_block(draft, f.get("placed_text", f["text"]))
                seen[f["sha256"]] = f["id"]
                if key: headings.setdefault(key, f["id"])
            plan["coverage"].append(entry)
        plan["deletes"].append({"path": rel, **file_state(path), "reason": "legacy consolidated"})
    if pointer_needed and wiki_for_scope:
        draft = append_block(draft, wiki_block(root / scope, root / wiki_for_scope))
    if draft != canonical_text or materialize:
        action = "materialize" if materialize else ("edit" if canonical_kind == "file" else "create")
        plan["outputs"].append({"path": canonical_rel, "action": action, "content": draft,
                                "before": file_state(root / canonical_rel)})
    # Deletes of aliases pointing at canonical must happen after canonical exists.
    plan["deletes"].sort(key=lambda d: d.get("kind") != "symlink")


IMPORT_LINE = re.compile(r"^\s*@([^\s@\[][^\s]*)\s*$")


def redirect_targets(fragment: dict[str, Any], base: Path, root: Path) -> set[str]:
    """Targets when every non-blank line is a Claude-style `@file` import; else empty."""
    targets = set()
    lines = [l for l in fragment["text"].splitlines() if l.strip()]
    if fragment["kind"] == "h1" or not lines: return set()
    for line in lines:
        match = IMPORT_LINE.match(line)
        if not match: return set()
        target = (base / match.group(1)).resolve()
        if not AUDIT.inside(target, root): return set()
        targets.add(target.relative_to(root).as_posix())
    return targets


def strip_h1(text: str) -> str:
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.strip():
            return "\n".join(lines[i + 1:]) if line.startswith("# ") else text
    return text


def append_block(draft: str, block: str) -> str:
    if not draft.strip(): return block if block.endswith("\n") else block + "\n"
    return draft.rstrip("\n") + "\n\n" + block.rstrip("\n") + "\n"


def pointer_resolves(fragment: dict[str, Any], base: Path, root: Path, wiki_rel: str | None) -> bool:
    raw = pointer_target(fragment["text"])
    if not raw or not wiki_rel: return False
    for suffix in ("/schema.md", "/index.md"):
        if raw.endswith(suffix): raw = raw[: -len(suffix)]
    if raw in ("schema.md", "index.md"): raw = "."
    candidate = Path(raw) if raw.startswith("/") else base / raw
    try:
        return candidate.resolve() == (root / wiki_rel).resolve()
    except OSError:
        return False


def inbound_refs(root: Path, deleted: list[str]) -> list[dict[str, str]]:
    if not deleted: return []
    names = sorted({Path(d).name for d in deleted})
    args = ["grep", "-n", "-I", "--fixed-strings"]
    for name in names: args += ["-e", name]
    proc = git(root, *args, check=False)
    refs = []
    for line in proc.stdout.splitlines():
        path, _, rest = line.partition(":")
        if path in deleted or Path(path).name in ("AGENTS.md", *names): continue
        number, _, text = rest.partition(":")
        refs.append({"path": path, "line": number, "text": text.strip()[:160]})
    return refs[:200]


def plan_status(plan: dict[str, Any]) -> str:
    if any(f["level"] == "blocked" for f in plan["findings"]): return "blocked"
    if any(not c.get("approved") for c in plan["coverage"]): return "needs-decision"
    if any(f["level"] == "decision" for f in plan["findings"]): return "needs-decision"
    return "ready"


# ---------------------------------------------------------------- check

def check(plan: dict[str, Any], root: Path, snapshot: bool = False) -> dict[str, Any]:
    root = root.resolve()
    errors: list[str] = []; warnings: list[str] = []; decisions: list[str] = []
    if plan.get("schema_version") != SCHEMA: errors.append("unsupported plan schema")
    if not snapshot and plan.get("root") and Path(plan["root"]).resolve() != root:
        errors.append("plan belongs to another repository root")
    for finding in plan.get("findings", []):
        if finding["level"] == "blocked": errors.append(f"blocked: {finding['code']} {finding.get('path', '')}".strip())
    if not snapshot:
        base = plan.get("base", {}).get("commit")
        if head_commit(root) != base: errors.append("HEAD moved since the plan was made; re-run plan")
    frag_by_id = {f["id"]: f for f in plan["fragments"]}
    for src in plan["sources"]:
        now = file_state(root / src["path"])
        if now.get("kind") != src.get("kind") or now.get("sha256") != src.get("sha256") or now.get("link_target") != src.get("link_target"):
            errors.append(f"stale source: {src['path']} changed since plan")
    for out in plan["outputs"]:
        if file_state(root / out["path"]) != out["before"]:
            errors.append(f"stale destination: {out['path']} changed since plan")
    outputs = {o["path"]: o["content"] for o in plan["outputs"]}
    deleted = {d["path"] for d in plan["deletes"]}
    final_text: dict[str, str] = {}
    for src in plan["sources"]:
        p = src["path"]
        if p in deleted: continue
        if p in outputs: final_text[p] = outputs[p]
        elif src["kind"] == "file": final_text[p] = (root / p).read_text(encoding="utf-8")
    for p, content in outputs.items(): final_text[p] = content
    # coverage
    covered: dict[str, int] = {}
    for entry in plan["coverage"]:
        fid = entry.get("fragment")
        if fid not in frag_by_id: errors.append(f"coverage references unknown fragment {fid}"); continue
        covered[fid] = covered.get(fid, 0) + 1
        frag = frag_by_id[fid]
        disp = entry.get("disposition")
        if disp not in ("canonical", "duplicate", "stub", "pointer", "placed", "dropped", "native", "private"):
            errors.append(f"{fid}: invalid disposition {disp}")
        if not entry.get("approved"): decisions.append(f"{fid}: {disp} not approved ({entry.get('note', frag['class'])})")
        dest = entry.get("destination")
        if disp == "placed":
            text = final_text.get(dest)
            if text is None: errors.append(f"{fid}: destination {dest} missing"); continue
            needle = norm_block(frag.get("placed_text", frag["text"]))
            if needle not in norm_block(text) and not entry.get("rewritten"):
                errors.append(f"{fid}: placed text not found in {dest} (mark rewritten after review)")
        if disp == "duplicate" and dest not in final_text:
            errors.append(f"{fid}: duplicate target {dest} missing")
        if disp in ("dropped", "native") and not entry.get("approved"):
            pass
    for f in plan["fragments"]:
        if f["class"] != "canonical" and covered.get(f["id"]) != 1:
            errors.append(f"{f['id']}: coverage must account for this fragment exactly once")
    # critical rules
    scope_texts: dict[str, str] = {}
    for p, t in final_text.items(): scope_texts[scope_of(p)] = scope_texts.get(scope_of(p), "") + "\n" + norm_space(t)
    for entry in plan["coverage"]:
        frag = frag_by_id.get(entry.get("fragment"))
        if not frag or entry.get("disposition") in ("stub", "pointer", "private", "native"): continue
        waived = {norm_space(w) for w in entry.get("critical_waived", [])} if entry.get("approved") else set()
        for line in frag.get("critical", []):
            if line in waived: continue
            if line not in scope_texts.get(frag["scope"], ""):
                errors.append(f"{frag['id']}: critical rule missing from consolidated output: {line[:90]}")
    # portability and agy rules
    for p, t in final_text.items():
        for line in t.splitlines():
            match = IMPORT_LINE.match(line)
            target = ((root / p).parent / match.group(1)).resolve() if match else None
            if target is not None and AUDIT.inside(target, root) and target.relative_to(root).as_posix() in deleted:
                errors.append(f"{p}: import {line.strip()} points at a deleted legacy file")
    for p, t in final_text.items():
        if AGY_INCLUDE.search(t) or any(CLAUDE_IMPORT.search(l) and l.lstrip().startswith("@") for l in t.splitlines()):
            if not plan.get("decisions", {}).get("includes_approved"):
                decisions.append(f"{p}: contains harness-specific includes; not resident for every CLI (approve includes or inline them)")
        if re.search(r"(^|/)\.agents/rules/[^/]+\.md$", p): errors.extend(agy_rule_errors(p, t))
        size = len(t.encode("utf-8"))
        if size > AGY_FILE_BUDGET: errors.append(f"{p}: {size} bytes exceeds agy {AGY_FILE_BUDGET}-byte per-file budget")
    cap, cap_note = codex_cap()
    if cap_note: warnings.append(cap_note)
    for cwd in plan.get("cwds", ["."]):
        total = codex_chain_bytes(root, cwd, final_text, deleted)
        if total > cap: errors.append(f"Codex chain for {cwd}: {total} bytes exceeds {cap}")
    # discovery invariance on the future tree
    try:
        future = future_selection(root, plan, final_text, deleted)
        for cwd, wiki in future.items():
            expected = plan.get("target", {}).get(cwd)
            if wiki["conflict"]: errors.append(f"future tree: same-level wiki conflict at {cwd}")
            elif wiki["selected"] != expected:
                errors.append(f"future tree: {cwd} selects {wiki['selected']} instead of {expected}")
    except MigrationError as exc:
        errors.append(f"future-tree discovery failed: {exc}")
    for ref in plan.get("inbound_refs", []): warnings.append(f"inbound reference {ref['path']}:{ref['line']} mentions a deleted legacy file")
    status = "blocked" if errors else ("needs-decision" if decisions else "ready")
    return {"ok": not errors and not decisions, "status": status, "errors": errors,
            "decisions_needed": decisions, "warnings": warnings}


def agy_rule_errors(path: str, text: str) -> list[str]:
    match = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not match: return [f"{path}: agy rule needs YAML frontmatter with trigger"]
    fields = dict(l.split(":", 1) for l in match.group(1).splitlines() if ":" in l)
    fields = {k.strip(): v.strip().strip('"') for k, v in fields.items()}
    trigger = fields.get("trigger")
    if trigger not in AGY_TRIGGERS: return [f"{path}: invalid agy trigger {trigger!r}"]
    if trigger == "glob" and not fields.get("globs"): return [f"{path}: glob trigger requires globs"]
    if trigger == "model_decision" and not fields.get("description"): return [f"{path}: model_decision requires description"]
    return []


def codex_cap() -> tuple[int, str | None]:
    config = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))) / "config.toml"
    if AUDIT.kind(config) != "file": return CODEX_CHAIN_DEFAULT, None
    try:
        import tomllib
        value = tomllib.loads(config.read_text(encoding="utf-8")).get("project_doc_max_bytes")
        if isinstance(value, int) and value > 0: return value, None
    except (OSError, ValueError, ImportError):
        return CODEX_CHAIN_DEFAULT, "Codex config unreadable; default 32 KiB chain budget assumed"
    return CODEX_CHAIN_DEFAULT, None


def codex_chain_bytes(root: Path, cwd: str, final_text: dict[str, str], deleted: set[str]) -> int:
    total = 0
    parts = [] if cwd == "." else Path(cwd).parts
    dirs = ["."] + ["/".join(parts[:i + 1]) for i in range(len(parts))]
    fallbacks, _ = AUDIT.default_fallbacks(Path.home())
    for d in dirs:
        for name in ("AGENTS.override.md", "AGENTS.md", *fallbacks):
            rel = name if d == "." else f"{d}/{name}"
            if rel in deleted: continue
            if rel in final_text: total += len(final_text[rel].encode("utf-8")); break
            if AUDIT.kind(root / rel) == "file": total += (root / rel).stat().st_size; break
    return total


def future_selection(root: Path, plan: dict[str, Any], final_text: dict[str, str], deleted: set[str]) -> dict[str, dict[str, Any]]:
    """Replay discovery on a temp tree: final instruction files plus empty wiki indexes."""
    with tempfile.TemporaryDirectory(prefix="wiki-future-") as tmp:
        sim = Path(tmp).resolve()
        subprocess.run(["git", "init", "-q", str(sim)], check=True, capture_output=True)
        for directory, dirs, files in os.walk(root, followlinks=False):
            dirs[:] = [d for d in dirs if d not in AUDIT.SKIP and not (Path(directory) / d).is_symlink()]
            rel_dir = Path(directory).relative_to(root)
            for name in files:
                rel = (rel_dir / name).as_posix()
                if name == "index.md":
                    target = sim / rel; target.parent.mkdir(parents=True, exist_ok=True); target.write_text("# index\n")
                elif name in ("AGENTS.md", "CLAUDE.md", "GEMINI.md", "QWEN.md") and rel not in deleted and rel not in final_text:
                    target = sim / rel; target.parent.mkdir(parents=True, exist_ok=True)
                    try: target.write_bytes((root / rel).read_bytes())
                    except OSError: pass
        for rel, content in final_text.items():
            target = sim / rel; target.parent.mkdir(parents=True, exist_ok=True); target.write_text(content, encoding="utf-8")
        result = {}
        for cwd in plan.get("cwds", ["."]):
            (sim / cwd).mkdir(parents=True, exist_ok=True)
            found = AUDIT.discovery(sim / cwd)
            result[cwd] = {"selected": rel_or_none(found["selected"], sim), "conflict": found["same_level_conflict"]}
        return result


# ---------------------------------------------------------------- apply / commit / rollback

def load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def save(path: Path, data: dict[str, Any]) -> None:
    write_private(path, json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def apply(plan: dict[str, Any], root: Path, write: bool) -> dict[str, Any]:
    root = root.resolve()
    report = check(plan, root)
    if not report["ok"]:
        raise MigrationError("plan is not ready: " + "; ".join(report["errors"] + report["decisions_needed"]))
    paths = [o["path"] for o in plan["outputs"]] + [d["path"] for d in plan["deletes"]]
    if not paths:
        return {"status": "noop", "detail": "instructions already consolidated"}
    if not write:
        return {"preview": True, "writes": [o["path"] for o in plan["outputs"]], "deletes": [d["path"] for d in plan["deletes"]]}
    mdir = migration_dir(root, plan["id"], create=True)
    state: dict[str, Any] = {"id": plan["id"], "base": plan["base"]["commit"], "status": "applying", "paths": {}}
    for rel in dict.fromkeys(paths):
        path = root / rel
        pre = file_state(path)
        tracked, clean = tracked_clean(root, rel) if pre["kind"] != "missing" else (False, False)
        pre.update(tracked=tracked, clean=clean, backup=None)
        if pre["kind"] == "file" and not clean:
            backup = mdir / "backup" / rel
            write_private(backup, path.read_bytes()); pre["backup"] = str(backup)
        state["paths"][rel] = pre
    save(mdir / "state.json", state)
    for out in plan["outputs"]:
        atomic_replace(root / out["path"], out["content"])
        state["paths"][out["path"]]["written_sha256"] = sha(out["content"])
    save(mdir / "state.json", state)
    for item in plan["deletes"]:
        path = root / item["path"]
        now = file_state(path)
        expected = {k: item[k] for k in ("kind", "sha256", "link_target") if k in item}
        if any(now.get(k) != v for k, v in expected.items()):
            state["status"] = "failed"; state["failed_at"] = item["path"]; save(mdir / "state.json", state)
            raise MigrationError(f"{item['path']} changed before delete; stopped with partial state (see rollback)")
        os.unlink(path)  # literal directory entry; a symlink target is never touched
        state["paths"][item["path"]]["deleted"] = True
        save(mdir / "state.json", state)
    mismatches = []
    for cwd in plan.get("cwds", ["."]):
        found = AUDIT.discovery(root / cwd) if (root / cwd).is_dir() else {"selected": None, "same_level_conflict": False}
        if rel_or_none(found["selected"], root) != plan["target"].get(cwd) or found["same_level_conflict"]:
            mismatches.append(cwd)
    state["status"] = "discovery-mismatch" if mismatches else "applied-uncommitted"
    state["public"] = [p for p in dict.fromkeys(paths)]
    save(mdir / "state.json", state)
    if mismatches: raise MigrationError(f"discovery changed after apply for {mismatches}; run rollback")
    return {"status": state["status"], "migration": str(mdir), "paths": state["public"]}


def commit(plan: dict[str, Any], root: Path, message: str) -> dict[str, Any]:
    root = root.resolve()
    mdir = migration_dir(root, plan["id"])
    if not plan["outputs"] and not plan["deletes"]:
        return {"status": "noop", "paths": []}
    state = load(mdir / "state.json")
    if state["status"] != "applied-uncommitted": raise MigrationError(f"cannot commit from state {state['status']}")
    paths = [rel for rel in state["public"]
             if state["paths"][rel].get("tracked") or os.path.lexists(root / rel)]
    for rel in paths:
        pre = state["paths"][rel]
        if pre["kind"] != "missing" and pre.get("tracked") and not pre.get("clean"):
            raise MigrationError(f"{rel} had pre-existing user changes; commit it manually after review")
    new_files = [rel for rel in paths if not state["paths"][rel].get("tracked") and (root / rel).exists()]
    if new_files: git(root, "add", "--", *new_files)
    git(root, "commit", "--only", "-q", "-m", message, "--", *paths)
    sha_commit = head_commit(root)
    changed = set(git(root, "show", "--name-only", "--format=", sha_commit).stdout.split())
    if changed != set(paths): raise MigrationError(f"commit content mismatch: {sorted(changed ^ set(paths))}")
    state.update(status="committed", commit=sha_commit); save(mdir / "state.json", state)
    return {"status": "committed", "commit": sha_commit, "paths": paths}


def rollback(plan: dict[str, Any], root: Path, write: bool, revert: bool = False) -> dict[str, Any]:
    root = root.resolve()
    mdir = migration_dir(root, plan["id"])
    state = load(mdir / "state.json")
    if state["status"] == "committed":
        if not revert: return {"status": "committed", "next": f"git revert {state['commit']} (or rerun with --revert)"}
        if write: git(root, "revert", "--no-edit", state["commit"])
        state["status"] = "reverted"; save(mdir / "state.json", state)
        return {"status": "reverted"}
    actions, skipped = [], []
    for rel, pre in state["paths"].items():
        path = root / rel
        now = file_state(path)
        written = pre.get("written_sha256")
        if written and now.get("sha256") != written and not pre.get("deleted"):
            skipped.append(f"{rel}: edited after migration; left as is"); continue
        if pre.get("deleted") and now["kind"] != "missing":
            skipped.append(f"{rel}: recreated after migration; left as is"); continue
        if not written and not pre.get("deleted"): continue
        actions.append(rel)
        if not write: continue
        if pre["kind"] == "missing":
            os.unlink(path)
        elif pre["kind"] == "symlink":
            if os.path.lexists(path): os.unlink(path)
            os.symlink(pre["link_target"], path)
        elif pre.get("backup"):
            atomic_replace(path, Path(pre["backup"]).read_text(encoding="utf-8"))
        elif pre.get("clean") and state.get("base"):
            git(root, "restore", f"--source={state['base']}", "--worktree", "--", rel)
        else:
            skipped.append(f"{rel}: no recovery source"); actions.remove(rel)
    if write:
        state["status"] = "rolled-back"; save(mdir / "state.json", state)
    return {"status": "rolled-back" if write else "preview", "restored": actions, "skipped": skipped}


# ---------------------------------------------------------------- private Claude rules (#13)

def private_dir(root: Path, source: str) -> Path:
    return migration_dir(root, "private-" + sha(source)[:12], create=True)


def private_state(root: Path, source: str) -> dict[str, Any]:
    path = private_dir(root, source) / "state.json"
    return load(path) if path.exists() else {"source": source, "status": "none"}


def rewrite_imports(text: str, src_dir: Path, dest_dir: Path) -> str:
    def fix(line: str) -> str:
        stripped = line.lstrip()
        if not stripped.startswith("@") or stripped.startswith(("@/", "@~", "@[")): return line
        target = stripped[1:].split()[0]
        new = Path(os.path.relpath(src_dir / target, dest_dir)).as_posix()
        return line.replace("@" + target, "@" + new, 1)
    return "".join(fix(l) for l in text.splitlines(keepends=True))


def private_prepare(root: Path, source: str, name: str, write: bool) -> dict[str, Any]:
    root = root.resolve()
    src = root / source
    if AUDIT.kind(src) != "file" or Path(source).name != PRIVATE: raise MigrationError("source must be a regular CLAUDE.local.md")
    if git(root, "ls-files", "--error-unmatch", "--", source, check=False).returncode == 0:
        raise MigrationError("CLAUDE.local.md is tracked: private content is already public; DECIDE separately")
    dest_rel = (Path(scope_of(source)) / ".claude/rules" / f"{name}.md").as_posix()
    if dest_rel.startswith("./"): dest_rel = dest_rel[2:]
    dest = root / dest_rel
    if os.path.lexists(dest): raise MigrationError(f"destination exists: {dest_rel}")
    content = rewrite_imports(src.read_text(encoding="utf-8"), src.parent, dest.parent)
    pattern = "/" + dest_rel
    if not write: return {"preview": True, "destination": dest_rel, "exclude": pattern}
    pdir = private_dir(root, source)
    write_private(pdir / "backup" / source, src.read_bytes())
    exclude = Path(git(root, "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip()) / "info" / "exclude"
    exclude.parent.mkdir(parents=True, exist_ok=True)
    existing = exclude.read_text(encoding="utf-8") if exclude.exists() else ""
    added = pattern not in existing.splitlines()
    if added:
        with exclude.open("a", encoding="utf-8") as stream:
            stream.write(("" if existing.endswith("\n") or not existing else "\n") + pattern + "\n")
    if git(root, "check-ignore", "-q", "--", dest_rel, check=False).returncode != 0:
        raise MigrationError("destination is not ignored by Git; stopped (original untouched)")
    if git(root, "ls-files", "--error-unmatch", "--", dest_rel, check=False).returncode == 0:
        raise MigrationError("destination is in the index; stopped")
    write_private(dest, content)
    state = {"source": source, "destination": dest_rel, "status": "prepared", "exclude": pattern,
             "exclude_added": added, "source_sha256": sha(src.read_bytes()), "dest_sha256": sha(content),
             "next": "checkpoint 1: in a NEW session at the right cwd confirm the rules file in /context"}
    save(pdir / "state.json", state)
    return state


def private_confirm(root: Path, source: str, checkpoint: int) -> dict[str, Any]:
    state = private_state(root, source)
    dest = root / state.get("destination", "")
    need = {1: "prepared", 2: "switched"}[checkpoint]
    if state["status"] != need: raise MigrationError(f"checkpoint {checkpoint} requires state {need}, got {state['status']}")
    if file_state(dest).get("sha256") != state["dest_sha256"]: raise MigrationError("rules file changed; re-run prepare")
    state["status"] = "checkpoint-1" if checkpoint == 1 else "completed"
    state[f"checkpoint_{checkpoint}_at"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    state["next"] = "switch" if checkpoint == 1 else None
    save(private_dir(root, source) / "state.json", state)
    return state


def private_switch(root: Path, source: str, write: bool) -> dict[str, Any]:
    state = private_state(root, source)
    if state["status"] != "checkpoint-1": raise MigrationError("switch requires checkpoint 1 (confirmed loading of the replacement)")
    src = root / source
    if file_state(src).get("sha256") != state["source_sha256"]: raise MigrationError("original changed since prepare; re-run prepare")
    if not write: return {"preview": True, "remove": source}
    os.unlink(src)
    state.update(status="switched", next="checkpoint 2: in a NEW session confirm rules in /context and AGENTS.md in /memory")
    save(private_dir(root, source) / "state.json", state)
    return state


def private_recover(root: Path, source: str, write: bool) -> dict[str, Any]:
    state = private_state(root, source)
    pdir = private_dir(root, source)
    if state["status"] == "none": raise MigrationError("no private migration state")
    actions = []
    if not (root / source).exists(): actions.append(f"restore {source}")
    dest = root / state["destination"]
    if file_state(dest).get("sha256") == state["dest_sha256"]: actions.append(f"remove {state['destination']}")
    if not write: return {"preview": True, "actions": actions}
    if not (root / source).exists(): write_private(root / source, (pdir / "backup" / source).read_bytes())
    if file_state(dest).get("sha256") == state["dest_sha256"]: os.unlink(dest)
    if state.get("exclude_added"):
        exclude = Path(git(root, "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip()) / "info" / "exclude"
        lines = exclude.read_text(encoding="utf-8").splitlines()
        if state["exclude"] in lines:
            lines.remove(state["exclude"]); exclude.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
    state["status"] = "recovered"; save(pdir / "state.json", state)
    return state


# ---------------------------------------------------------------- CLI

def plan_path(root: Path, plan_id: str) -> Path:
    return migration_dir(root, plan_id) / "plan.json"


def summary(plan: dict[str, Any]) -> dict[str, Any]:
    classes: dict[str, int] = {}
    for f in plan["fragments"]: classes[f["class"]] = classes.get(f["class"], 0) + 1
    return {"id": plan["id"], "status": plan["status"], "outputs": [o["path"] for o in plan["outputs"]],
            "deletes": [d["path"] for d in plan["deletes"]], "classes": classes,
            "needs_decision": [c["fragment"] for c in plan["coverage"] if not c.get("approved")],
            "findings": plan["findings"], "inbound_refs": len(plan.get("inbound_refs", [])), "private": plan["private"]}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("plan"); p.add_argument("--project", default=".")
    for name in ("check", "apply", "commit", "rollback", "approve", "show"):
        c = sub.add_parser(name); c.add_argument("--project", default="."); c.add_argument("--plan", required=True)
        if name == "check": c.add_argument("--snapshot", help="validate against this directory (remote/pinned snapshot); no Git base checks")
        if name in ("apply", "rollback"): c.add_argument("--write", action="store_true")
        if name == "rollback": c.add_argument("--revert", action="store_true")
        if name == "commit": c.add_argument("--message", default="wiki: consolidate instructions into AGENTS.md")
        if name == "approve":
            c.add_argument("--fragment", action="append", default=[]); c.add_argument("--all", action="store_true")
            c.add_argument("--rewritten", action="store_true"); c.add_argument("--includes", action="store_true")
            c.add_argument("--skip-optimization", action="store_true")
    v = sub.add_parser("private"); v.add_argument("action", choices=("prepare", "confirm", "switch", "recover", "status"))
    v.add_argument("--project", default="."); v.add_argument("--source", required=True)
    v.add_argument("--name", default="local"); v.add_argument("--checkpoint", type=int, choices=(1, 2))
    v.add_argument("--write", action="store_true")
    args = parser.parse_args(argv)
    try:
        project = Path(args.project).resolve()
        root = Path(git(project, "rev-parse", "--show-toplevel").stdout.strip()).resolve() if not getattr(args, "snapshot", None) else Path(args.snapshot).resolve()
        if args.command == "private":
            if args.action == "confirm" and not args.checkpoint: raise MigrationError("--checkpoint 1|2 required")
            result = {"prepare": lambda: private_prepare(root, args.source, args.name, args.write),
                      "confirm": lambda: private_confirm(root, args.source, args.checkpoint),
                      "switch": lambda: private_switch(root, args.source, args.write),
                      "recover": lambda: private_recover(root, args.source, args.write),
                      "status": lambda: private_state(root, args.source)}[args.action]()
            print(json.dumps(result, ensure_ascii=False, indent=2)); return 0
        if args.command == "plan":
            plan = build_plan(project)
            path = migration_dir(root, plan["id"], create=True) / "plan.json"
            save(path, plan)
            print(json.dumps({"plan": str(path), **summary(plan)}, ensure_ascii=False, indent=2))
            return 0 if plan["status"] != "blocked" else 2
        path = Path(args.plan)
        plan = load(path)
        if args.command == "show":
            print(json.dumps(summary(plan), ensure_ascii=False, indent=2)); return 0
        if args.command == "approve":
            for entry in plan["coverage"]:
                if args.all or entry["fragment"] in args.fragment:
                    entry["approved"] = True
                    if args.rewritten: entry["rewritten"] = True
            if args.includes: plan["decisions"]["includes_approved"] = True
            if args.skip_optimization: plan["optimization"]["skipped"] = True
            plan["status"] = plan_status(plan); save(path, plan)
            print(json.dumps(summary(plan), ensure_ascii=False, indent=2)); return 0
        if args.command == "check":
            report = check(plan, root, snapshot=bool(args.snapshot))
            print(json.dumps(report, ensure_ascii=False, indent=2)); return 0 if report["ok"] else 2
        if args.command == "apply":
            print(json.dumps(apply(plan, root, args.write), ensure_ascii=False, indent=2)); return 0
        if args.command == "commit":
            print(json.dumps(commit(plan, root, args.message), ensure_ascii=False, indent=2)); return 0
        if args.command == "rollback":
            print(json.dumps(rollback(plan, root, args.write, args.revert), ensure_ascii=False, indent=2)); return 0
    except (MigrationError, OSError, ValueError, subprocess.SubprocessError, KeyError) as exc:
        print(f"wiki migrate: {exc}", file=sys.stderr)
        return 2
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
