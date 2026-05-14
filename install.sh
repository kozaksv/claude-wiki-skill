#!/bin/bash
set -e

WIKI_VERSION="${1:-master}"

REPO="https://github.com/kozaksv/claude-wiki-skill.git"
SKILL_DIR="$HOME/claude-wiki-skill"
SKILLS_ROOT="$HOME/.claude/skills"
SKILL_LINK="$SKILLS_ROOT/wiki"
AGENTS_SKILLS_ROOT="$HOME/.agents/skills"
GEMINI_SKILLS_ROOT="$HOME/.gemini/skills"

DOC_EXTRACT_REPO="https://github.com/kozaksv/claude-doc-extract-skill.git"
DOC_EXTRACT_DIR="$HOME/claude-doc-extract-skill"
DOC_EXTRACT_LINK="$SKILLS_ROOT/doc-extract"
DOC_EXTRACT_REF="main"

set_skill_link() {
  local name="$1" target_dir="$2" link="$3"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "Помилка: $link вже існує і не є symlink. Видаліть або перейменуйте вручну і спробуйте знову."
    return 1
  fi
  ln -sfn "$target_dir" "$link"
}

install_skill_at_ref() {
  local name="$1" repo="$2" dir="$3" link="$4" ref="$5"
  if [ -d "$dir/.git" ]; then
    echo "[$name] репо вже існує — переключаю на $ref..."
    git -C "$dir" fetch --tags --force origin || return 1
    git -C "$dir" checkout "$ref" || return 1
    if git -C "$dir" symbolic-ref -q HEAD >/dev/null; then
      git -C "$dir" pull --ff-only || return 1
    fi
  else
    if [ -e "$dir" ]; then
      echo "Помилка: $dir існує, але це не git-репо. Видаліть вручну і спробуйте знову."
      return 1
    fi
    echo "[$name] клоную $repo → $dir..."
    git clone "$repo" "$dir" || return 1
    git -C "$dir" checkout "$ref" || return 1
  fi
  set_skill_link "$name" "$dir" "$link"
}

export_skill_link() {
  local name="$1" source_link="$2" export_link="$3"
  local export_root
  export_root="$(dirname "$export_link")"
  mkdir -p "$export_root"

  if [ -L "$export_link" ]; then
    local current
    current="$(readlink "$export_link")"
    if [ "$current" = "$source_link" ]; then
      echo "[$name] export вже існує: $export_link → $source_link"
      return 0
    fi
    if [ ! -e "$export_link" ]; then
      echo "[$name] замінюю битий export: $export_link"
      ln -sfn "$source_link" "$export_link"
      return 0
    fi
    echo "Увага: $export_link вже вказує на $current — не перезаписую."
    return 0
  fi

  if [ -e "$export_link" ]; then
    echo "Увага: $export_link вже існує і не є symlink — не перезаписую."
    return 0
  fi

  ln -s "$source_link" "$export_link"
  echo "[$name] export: $export_link → $source_link"
}

echo "=== Wiki Skill — встановлення (версія: $WIKI_VERSION) ==="

if ! command -v git &>/dev/null; then
  echo "Помилка: git не встановлений. Встановіть git і спробуйте знову."
  exit 1
fi

mkdir -p "$SKILLS_ROOT"

# 1. Wiki skill — користувацький pin (за замовчуванням master)
install_skill_at_ref "wiki" "$REPO" "$SKILL_DIR" "$SKILL_LINK" "$WIKI_VERSION"

# 2. Cross-agent wiki exports — Claude лишається canonical registry.
# Codex uses ~/.agents/skills as its shared user skill path in the current
# Codex skill runtime. Gemini CLI documents ~/.gemini/skills and
# ~/.agents/skills as user-skill discovery locations:
# https://geminicli.com/docs/cli/using-agent-skills/#discovery-tiers
# Лінкуємо на Claude entrypoint, не на realpath, щоб перемикання Claude-версії
# автоматично підхоплювали Codex і Gemini.
export_skill_link "wiki" "$SKILL_LINK" "$AGENTS_SKILLS_ROOT/wiki"
export_skill_link "wiki" "$SKILL_LINK" "$GEMINI_SKILLS_ROOT/wiki"

# 3. doc-extract (optional dependency for ingest-binary). Keep wiki available
# even if this dependency cannot be installed; text/source wiki operations still work.
DOC_EXTRACT_INSTALLED=0
if install_skill_at_ref "doc-extract" "$DOC_EXTRACT_REPO" "$DOC_EXTRACT_DIR" "$DOC_EXTRACT_LINK" "$DOC_EXTRACT_REF"; then
  DOC_EXTRACT_INSTALLED=1
  export_skill_link "doc-extract" "$DOC_EXTRACT_LINK" "$AGENTS_SKILLS_ROOT/doc-extract"
  export_skill_link "doc-extract" "$DOC_EXTRACT_LINK" "$GEMINI_SKILLS_ROOT/doc-extract"
else
  echo "Увага: doc-extract не встановлено. Wiki skill працюватиме, але ingest-binary буде недоступний до повторного встановлення."
fi

echo ""
echo "Готово! Встановлено:"
echo "  $SKILL_LINK → $SKILL_DIR  (@ $WIKI_VERSION)"
echo "Cross-agent exports (symlinks to Claude canonical):"
echo "  $AGENTS_SKILLS_ROOT/wiki → $SKILL_LINK"
echo "  $GEMINI_SKILLS_ROOT/wiki → $SKILL_LINK"
if [ "$DOC_EXTRACT_INSTALLED" -eq 1 ]; then
  echo "  $DOC_EXTRACT_LINK → $DOC_EXTRACT_DIR  (@ $DOC_EXTRACT_REF)"
  echo "  $AGENTS_SKILLS_ROOT/doc-extract → $DOC_EXTRACT_LINK"
  echo "  $GEMINI_SKILLS_ROOT/doc-extract → $DOC_EXTRACT_LINK"
fi
if [ "$DOC_EXTRACT_INSTALLED" -eq 1 ]; then
  echo ""
  echo "Для роботи з PDF/DOCX (ingest-binary) встановіть системні залежності:"
  echo "  bash $DOC_EXTRACT_LINK/bin/install-deps.sh"
  echo "  bash $DOC_EXTRACT_LINK/bin/doctor.sh"
else
  echo ""
  echo "Для роботи з PDF/DOCX (ingest-binary) повторіть інсталяцію після виправлення doc-extract доступу."
fi
echo ""
echo "Відкрийте проєкт у Claude Code, Codex або Gemini CLI і скажіть: створи вікі"
