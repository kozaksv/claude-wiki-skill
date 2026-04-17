#!/bin/bash
set -e

REPO="https://github.com/kozaksv/claude-wiki-skill.git"
SKILL_DIR="$HOME/claude-wiki-skill"
SKILLS_ROOT="$HOME/.claude/skills"
SKILL_LINK="$SKILLS_ROOT/wiki"

DOC_EXTRACT_REPO="https://github.com/kozaksv/claude-doc-extract-skill.git"
DOC_EXTRACT_DIR="$HOME/claude-doc-extract-skill"
DOC_EXTRACT_LINK="$SKILLS_ROOT/doc-extract"

install_skill() {
  local name="$1" repo="$2" dir="$3" link="$4"
  if [ -d "$dir/.git" ]; then
    echo "[$name] репо вже існує — оновлюю..."
    git -C "$dir" pull
  else
    if [ -e "$dir" ]; then
      echo "Помилка: $dir існує, але це не git-репо. Видаліть вручну і спробуйте знову."
      exit 1
    fi
    echo "[$name] клоную $repo → $dir..."
    git clone "$repo" "$dir"
  fi
  ln -sfn "$dir" "$link"
}

echo "=== Claude Wiki Skill — встановлення ==="

if ! command -v git &>/dev/null; then
  echo "Помилка: git не встановлений. Встановіть git і спробуйте знову."
  exit 1
fi

mkdir -p "$SKILLS_ROOT"

# 1. Wiki skill
install_skill "wiki" "$REPO" "$SKILL_DIR" "$SKILL_LINK"

# 2. doc-extract (залежність для ingest-binary)
install_skill "doc-extract" "$DOC_EXTRACT_REPO" "$DOC_EXTRACT_DIR" "$DOC_EXTRACT_LINK"

echo ""
echo "Готово! Встановлено:"
echo "  $SKILL_LINK → $SKILL_DIR"
echo "  $DOC_EXTRACT_LINK → $DOC_EXTRACT_DIR"
echo ""
echo "Для роботи з PDF/DOCX (ingest-binary) встановіть системні залежності:"
echo "  bash $DOC_EXTRACT_LINK/bin/install-deps.sh"
echo "  bash $DOC_EXTRACT_LINK/bin/doctor.sh"
echo ""
echo "Відкрийте проєкт у Claude Code і скажіть: створи вікі"
