#!/bin/bash
set -euo pipefail

# Pipe-safe: bash parses this whole brace group before running any of it, so
# `curl … | bash` cannot execute a truncated download, and child commands never
# read the rest of the script from stdin.
{

# Execute a stable copy: checkout may replace the installer currently running.
if [ "${WIKI_INSTALL_RUNNING_COPY:-}" != "1" ] && [ -f "${BASH_SOURCE[0]:-}" ]; then
  installer_copy="$(mktemp)"
  cat "${BASH_SOURCE[0]}" >"$installer_copy"
  copy_rc=0
  WIKI_INSTALL_RUNNING_COPY=1 WIKI_INSTALL_SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" bash "$installer_copy" "$@" || copy_rc=$?
  rm -f "$installer_copy"
  exit "$copy_rc"
fi

REPAIR_EXPORTS=0
SKIP_HOOKS=0
WIKI_VERSION=master
REF_GIVEN=0
PROJECT_ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repair-exports)
      [ "$#" -eq 1 ] && [ "$REF_GIVEN" -eq 0 ] && [ "${#PROJECT_ARGS[@]}" -eq 0 ] && [ "$SKIP_HOOKS" -eq 0 ] || {
        echo 'Помилка: --repair-exports не приймає аргументів.' >&2; exit 2;
      }
      REPAIR_EXPORTS=1; shift ;;
    --skip-hooks) SKIP_HOOKS=1; shift ;;
    --project)
      [ "$#" -ge 2 ] && [ -n "$2" ] || { echo 'Помилка: --project потребує шляху.' >&2; exit 2; }
      PROJECT_ARGS+=(--project "$2"); shift 2 ;;
    --help|-h)
      echo 'usage: install.sh [ref] [--project PATH ...] [--skip-hooks] | --repair-exports'
      exit 0 ;;
    --*) echo "Помилка: невідомий параметр $1" >&2; exit 2 ;;
    *)
      [ "$REF_GIVEN" -eq 0 ] || { echo 'Помилка: дозволений лише один ref.' >&2; exit 2; }
      WIKI_VERSION="$1"; REF_GIVEN=1; shift ;;
  esac
done

REPO="https://github.com/kozaksv/claude-wiki-skill.git"
SKILL_DIR="$HOME/claude-wiki-skill"
SKILLS_ROOT="$HOME/.claude/skills"
SKILL_LINK="$SKILLS_ROOT/wiki"

DOC_EXTRACT_REPO="https://github.com/kozaksv/claude-doc-extract-skill.git"
DOC_EXTRACT_DIR="$HOME/claude-doc-extract-skill"
DOC_EXTRACT_LINK="$SKILLS_ROOT/doc-extract"
DOC_EXTRACT_REF="${WIKI_DOC_EXTRACT_REF:-51f720ff620478688abf7d906d18112d45e28a90}"

validate_ref() {
  local label="$1" ref="$2"
  if [[ ! "$ref" =~ ^[A-Za-z0-9._/-]+$ ]] ||
     [[ "$ref" == -* ]] ||
     [[ "$ref" == *..* ]]; then
    echo "Помилка: invalid $label ref '$ref'. Дозволені символи: A-Z a-z 0-9 . _ / -; ref не може починатися з '-' або містити '..'."
    return 1
  fi
}

set_skill_link() {
  local name="$1" target_dir="$2" link="$3"
  if [ -L "$link" ]; then
    local current
    current="$(readlink "$link")"
    if [ "$current" = "$target_dir" ]; then
      return 0
    fi
    echo "Помилка: $link вже вказує на $current — не перезаписую canonical link. Видаліть його вручну або перемкніть самостійно."
    return 1
  fi
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "Помилка: $link вже існує і не є symlink. Видаліть або перейменуйте вручну і спробуйте знову."
    return 1
  fi
  ln -sfn "$target_dir" "$link"
}

ensure_ref_exists() {
  local name="$1" dir="$2" ref="$3"
  if git -C "$dir" rev-parse --verify --quiet "$ref^{commit}" >/dev/null ||
     git -C "$dir" rev-parse --verify --quiet "origin/$ref^{commit}" >/dev/null; then
    return 0
  fi
  echo "Помилка: ref '$ref' не знайдено для $name. Перевірте доступні теги/гілки або запустіть без аргумента для master."
  return 1
}

install_skill_at_ref() {
  local name="$1" repo="$2" dir="$3" link="$4" ref="$5"
  if [ -d "$dir/.git" ]; then
    if [ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]; then
      echo "Помилка: $dir містить локальні зміни — збережіть їх перед оновленням; reset/stash не виконується." >&2
      return 1
    fi
    echo "[$name] репо вже існує — переключаю на $ref..."
    git -C "$dir" fetch --tags --force origin || {
      echo "Помилка: не вдалося оновити $dir. Якщо це partial або corrupt clone після обірваного git clone, перейменуйте/видаліть цю директорію і запустіть installer повторно."
      return 1
    }
    ensure_ref_exists "$name" "$dir" "$ref" || return 1
    git -C "$dir" checkout "$ref" || return 1
    if git -C "$dir" symbolic-ref -q HEAD >/dev/null; then
      git -C "$dir" pull --ff-only || {
        echo "Помилка: неможливо оновити $dir (можливо, є локальні зміни або git-конфлікт)."
        return 1
      }
      if git -C "$dir" rev-parse --verify --quiet "origin/$ref^{commit}" >/dev/null; then
        if [ "$(git -C "$dir" rev-parse HEAD)" != "$(git -C "$dir" rev-parse "origin/$ref^{commit}")" ]; then
          echo "Помилка: локальна гілка $ref відрізняється від origin/$ref; не оголошую оновлення успішним." >&2
          return 1
        fi
      fi
    fi
  else
    if [ -e "$dir" ]; then
      echo "Помилка: $dir існує, але це не git-репо. Видаліть вручну і спробуйте знову."
      return 1
    fi
    echo "[$name] клоную $repo → $dir..."
    git clone "$repo" "$dir" || return 1
    ensure_ref_exists "$name" "$dir" "$ref" || return 1
    git -C "$dir" checkout "$ref" || return 1
  fi
  set_skill_link "$name" "$dir" "$link"
}

HARNESS_REGISTRY_READY=0
load_harness_registry() {
  [ "$HARNESS_REGISTRY_READY" = 0 ] || return 0
  local registry
  if [ -n "${WIKI_INSTALL_SOURCE_DIR:-}" ]; then
    registry="$WIKI_INSTALL_SOURCE_DIR/lib/harnesses.sh"
    if [ -f "$registry" ] && [ -f "$WIKI_INSTALL_SOURCE_DIR/SKILL.md" ] &&
       [ -f "$WIKI_INSTALL_SOURCE_DIR/install.sh" ] &&
       cmp -s "$WIKI_INSTALL_SOURCE_DIR/install.sh" "${BASH_SOURCE[0]}"; then
      source "$registry"
      HARNESS_REGISTRY_READY=1
      return 0
    fi
  fi
  registry="$SKILL_DIR/lib/harnesses.sh"
  if [ -L "$SKILL_LINK" ] && [ "$(readlink "$SKILL_LINK")" = "$SKILL_DIR" ] &&
     [ -d "$SKILL_DIR/.git" ] && [ -f "$registry" ]; then
    source "$registry"
    HARNESS_REGISTRY_READY=1
    return 0
  fi
  echo 'wiki: harness registry unavailable in this pinned ref; exports not verified' >&2
  return 1
}

# Retain an available current registry in memory before checkout changes refs.
load_harness_registry 2>/dev/null || true

repair_cross_agent_exports() {
  echo "=== Wiki Skill — repair cross-agent exports ==="

  if [ ! -e "$SKILL_LINK" ] && [ ! -L "$SKILL_LINK" ]; then
    echo "Помилка: canonical wiki entrypoint не знайдено: $SKILL_LINK"
    echo "Запустіть повну інсталяцію: bash install.sh"
    return 1
  fi
  if [ ! -L "$SKILL_LINK" ]; then
    echo "Помилка: canonical wiki entrypoint не є symlink: $SKILL_LINK"
    echo "Перевірте цей шлях вручну або запустіть повну інсталяцію після перейменування конфлікту."
    return 1
  fi
  if [ ! -e "$SKILL_LINK" ]; then
    echo "Помилка: битий canonical wiki symlink: $SKILL_LINK → $(readlink "$SKILL_LINK")"
    echo "Перевірте шлях і target вручну. Installer не замінює цей link автоматично."
    printf 'Після перевірки видаліть лише сам битий symlink (без -r): rm -- %q\n' "$SKILL_LINK"
    echo "Потім запустіть повну інсталяцію зі свіжого installer: bash install.sh"
    return 1
  fi
  if [ ! -f "$SKILL_LINK/SKILL.md" ]; then
    echo "Помилка: canonical wiki entrypoint не містить SKILL.md: $SKILL_LINK"
    echo "Запустіть повну інсталяцію: bash install.sh"
    return 1
  fi

  load_harness_registry || return 2
  echo "Cross-agent export targets:"
  wiki_reconcile_exports
}

if [ "$REPAIR_EXPORTS" -eq 1 ]; then
  repair_cross_agent_exports
  exit $?
fi

echo "=== Wiki Skill — встановлення (версія: $WIKI_VERSION) ==="

validate_ref "install" "$WIKI_VERSION" || exit 2
validate_ref "doc-extract" "$DOC_EXTRACT_REF" || exit 2

if ! command -v git &>/dev/null; then
  echo "Помилка: git не встановлений. Встановіть git і спробуйте знову."
  exit 1
fi

if [ "${#PROJECT_ARGS[@]}" -eq 0 ]; then
  current_project="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$current_project" ] && [ "$current_project" != "$HOME" ] && [ "$current_project" != "$SKILL_DIR" ]; then
    PROJECT_ARGS+=(--project "$current_project")
  fi
fi
mkdir -p "$SKILLS_ROOT"

# 1. Wiki skill — користувацький pin (за замовчуванням master)
install_skill_at_ref "wiki" "$REPO" "$SKILL_DIR" "$SKILL_LINK" "$WIKI_VERSION"

# 2. Optional extractor. The shared registry exports only installed skills.
DOC_EXTRACT_INSTALLED=0
if install_skill_at_ref "doc-extract" "$DOC_EXTRACT_REPO" "$DOC_EXTRACT_DIR" "$DOC_EXTRACT_LINK" "$DOC_EXTRACT_REF"; then
  DOC_EXTRACT_INSTALLED=1
else
  echo "Увага: doc-extract не встановлено. Wiki skill працюватиме, але ingest-binary буде недоступний до повторного встановлення."
fi

# 3. Active exports and exact-owned retirement use one lifecycle.
EXPORTS_STATUS=0
if load_harness_registry; then
  wiki_reconcile_exports || EXPORTS_STATUS=$?
else
  EXPORTS_STATUS=2
fi

# 4. Git hooks (best-effort). Registers the wiki skill's global Claude Code
# hooks (SessionStart, PostToolUse) into ~/.claude/settings.json via the
# canonical entrypoint. A failure here must never abort the wiki install —
# text/source wiki operations work fine without hooks; only the automated
# session-start/log-rotation conveniences are lost.
HOOKS_STATUS="absent"
if [ "$SKIP_HOOKS" -eq 1 ]; then
  HOOKS_STATUS="skipped"
elif ! command -v python3 >/dev/null 2>&1; then
  HOOKS_STATUS="failed"
  echo 'Увага: python3 недоступний — скіл оновлено, але hooks не оновлено/не перевірено.' >&2
elif [ -f "$SKILL_LINK/hooks/install-hooks.sh" ]; then
  if [ -f "$SKILL_LINK/hooks/lib/config_audit.py" ]; then
    if bash "$SKILL_LINK/hooks/install-hooks.sh" --verify ${PROJECT_ARGS[@]+"${PROJECT_ARGS[@]}"}; then
      HOOKS_STATUS="ok"
    else
      HOOKS_STATUS="failed"
      echo 'Увага: оновлення hooks неповне; дивіться конкретні причини вище.' >&2
    fi
  else
    # A deliberately pinned old ref need not ship the new audit protocol.
    if bash "$SKILL_LINK/hooks/install-hooks.sh"; then
      HOOKS_STATUS="legacy"
      echo 'Увага: цей старий ref не підтримує міграцію/аудит проєктних hooks; verified не підтверджено.' >&2
    else
      HOOKS_STATUS="failed"
    fi
  fi
else
  echo "Увага: install-hooks.sh не знайдено в $SKILL_LINK/hooks — хуки не зареєстровано."
fi

ANY_SKIPPED=0
[ "$EXPORTS_STATUS" -eq 0 ] || ANY_SKIPPED=1

echo ""
echo "Скіл встановлено/оновлено; статус hooks наведено окремо:"
echo "  commit: $(git -C "$SKILL_DIR" rev-parse HEAD)"
echo "  $SKILL_LINK → $SKILL_DIR  (@ $WIKI_VERSION)"
echo "  Примітка: ~/.claude/skills — це shared canonical registry; Claude Code не потрібен."
echo "Cross-agent exports: detailed results above (not runtime verification)"
if [ "$DOC_EXTRACT_INSTALLED" -eq 1 ]; then
  echo "  $DOC_EXTRACT_LINK → $DOC_EXTRACT_DIR  (@ $DOC_EXTRACT_REF)"
fi
echo "Session-хуки Claude Code:"
case "$HOOKS_STATUS" in
  ok)
    echo "  зареєстровано в $HOME/.claude/settings.json (SessionStart + PostToolUse)"
    echo "  перевірено в зазначеній області; нова сесія зручна для чистої перевірки виводу"
    ;;
  skipped)
    echo "  пропущено явно (--skip-hooks); скіл працює без автоматичних hooks"
    ;;
  legacy)
    echo "  реєстрація виконана старим ref; міграцію/аудит не підтверджено"
    ;;
  failed)
    echo "  не зареєстровано — крок завершився помилкою (повідомлення вище)"
    ;;
  absent)
    echo "  не зареєстровано — install-hooks.sh не знайдено у скілі"
    ;;
esac
if [ "$ANY_SKIPPED" -eq 1 ]; then
  echo ""
  echo "Увага: частину exports пропущено. Summary вище показує фактичний стан кожного шляху —"
  echo "Codex/agy/Qwen бачитимуть лише ті exports, які реально існують і ведуть на canonical."
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
echo "Відкрийте проєкт у Claude Code, Codex, agy CLI або Qwen Code і скажіть: створи вікі"

# Partial hook updates must be visible to callers/CI, not only in scrollback.
[ "$HOOKS_STATUS" != "failed" ] || exit 3
}
