#!/bin/bash
set -e

REPO="https://github.com/kozaksv/claude-wiki-skill.git"
SKILL_DIR="$HOME/claude-wiki-skill"
SKILLS_ROOT="$HOME/.claude/skills"
SKILL_LINK="$SKILLS_ROOT/wiki"

echo "=== Claude Wiki Skill — встановлення ==="

# 1. Перевірка git
if ! command -v git &>/dev/null; then
  echo "Помилка: git не встановлений. Встановіть git і спробуйте знову."
  exit 1
fi

# 2. Клонування або оновлення
if [ -d "$SKILL_DIR/.git" ]; then
  echo "Репо вже існує в $SKILL_DIR — оновлюю..."
  git -C "$SKILL_DIR" pull
else
  if [ -e "$SKILL_DIR" ]; then
    echo "Помилка: $SKILL_DIR існує, але це не git-репо. Видаліть вручну і спробуйте знову."
    exit 1
  fi
  echo "Клоную $REPO → $SKILL_DIR..."
  git clone "$REPO" "$SKILL_DIR"
fi

# 3. Створення теки skills
mkdir -p "$SKILLS_ROOT"

# 4. Симлінк
ln -sfn "$SKILL_DIR" "$SKILL_LINK"

echo ""
echo "Готово! Скіл встановлено:"
echo "  $SKILL_LINK → $SKILL_DIR"
echo ""
echo "Відкрийте проєкт у Claude Code і скажіть: створи вікі"
