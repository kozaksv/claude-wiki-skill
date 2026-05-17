#!/bin/bash
set -euo pipefail

REPAIR_EXPORTS=0
if [ "${1:-}" = "--repair-exports" ]; then
  REPAIR_EXPORTS=1
  shift
  if [ -n "${1:-}" ]; then
    echo "Помилка: --repair-exports не приймає аргументів. Для переключення версії запустіть install.sh <ref> без --repair-exports."
    exit 2
  fi
fi

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
DOC_EXTRACT_REF="${WIKI_DOC_EXTRACT_REF:-96d6bf9e1df309c4b76d924d3a1f774f7ee33d12}"

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
    if [ ! -e "$link" ]; then
      echo "[$name] замінюю битий canonical link: $link"
      ln -sfn "$target_dir" "$link"
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

export_skill_link() {
  local name="$1" source_link="$2" export_link="$3"
  local export_root
  export_root="$(dirname "$export_link")"
  local probe="$export_root"
  while [ ! -e "$probe" ]; do
    local parent
    parent="$(dirname "$probe")"
    [ "$parent" = "$probe" ] && break
    probe="$parent"
  done
  if [ -e "$probe" ] && [ ! -d "$probe" ]; then
    echo "Увага: export root $probe існує і не є директорією — export пропущено."
    return 2
  fi
  if ! mkdir -p "$export_root"; then
    echo "Увага: Не вдалося створити export directory: $export_root — export пропущено."
    return 2
  fi

  if [ -L "$export_link" ]; then
    local current
    current="$(readlink "$export_link")"
    if [ "$current" = "$source_link" ]; then
      echo "[$name] export вже існує: $export_link → $source_link"
      return 0
    fi
    if [ ! -e "$export_link" ]; then
      echo "[$name] замінюю битий export: $export_link"
      if ln -sfn "$source_link" "$export_link"; then
        return 0
      fi
      echo "Увага: Не вдалося створити export: $export_link → $source_link"
      return 2
    fi
    echo "Увага: $export_link вже вказує на $current — не перезаписую."
    return 2
  fi

  if [ -e "$export_link" ]; then
    echo "Увага: $export_link вже існує і не є symlink — не перезаписую."
    return 2
  fi

  if ln -s "$source_link" "$export_link"; then
    echo "[$name] export: $export_link → $source_link"
    return 0
  fi
  echo "Увага: Не вдалося створити export: $export_link → $source_link"
  return 2
}

status_tag() {
  case "$1" in
    skipped) printf '  (пропущено)' ;;
    *)       : ;;
  esac
}

print_export_summary() {
  local link="$1" expected="$2" status="$3"
  if [ -L "$link" ]; then
    local current
    current="$(readlink "$link")"
    if [ "$current" = "$expected" ]; then
      echo "  $link → $current"
    else
      echo "  $link → $current$(status_tag "$status"; printf ' — expected %s' "$expected")"
    fi
    return 0
  fi
  if [ -e "$link" ]; then
    echo "  $link$(status_tag "$status"; printf ' — існує і не є symlink; expected %s' "$expected")"
    return 0
  fi
  echo "  $link$(status_tag "$status"; printf ' — не створено; expected %s' "$expected")"
}

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
    echo "Запустіть повну інсталяцію: bash install.sh"
    return 1
  fi
  if [ ! -f "$SKILL_LINK/SKILL.md" ]; then
    echo "Помилка: canonical wiki entrypoint не містить SKILL.md: $SKILL_LINK"
    echo "Запустіть повну інсталяцію: bash install.sh"
    return 1
  fi

  local wiki_agents_status="ok"
  local wiki_gemini_status="ok"
  local doc_agents_status="ok"
  local doc_gemini_status="ok"
  local doc_extract_present=0

  if ! export_skill_link "wiki" "$SKILL_LINK" "$AGENTS_SKILLS_ROOT/wiki"; then
    wiki_agents_status="skipped"
  fi
  if ! export_skill_link "wiki" "$SKILL_LINK" "$GEMINI_SKILLS_ROOT/wiki"; then
    wiki_gemini_status="skipped"
  fi

  if [ -e "$DOC_EXTRACT_LINK/SKILL.md" ]; then
    doc_extract_present=1
    if ! export_skill_link "doc-extract" "$DOC_EXTRACT_LINK" "$AGENTS_SKILLS_ROOT/doc-extract"; then
      doc_agents_status="skipped"
    fi
    if ! export_skill_link "doc-extract" "$DOC_EXTRACT_LINK" "$GEMINI_SKILLS_ROOT/doc-extract"; then
      doc_gemini_status="skipped"
    fi
  fi

  local any_skipped=0
  for status in "$wiki_agents_status" "$wiki_gemini_status" "$doc_agents_status" "$doc_gemini_status"; do
    [ "$status" = "skipped" ] && any_skipped=1
  done

  echo ""
  echo "Cross-agent export targets:"
  print_export_summary "$AGENTS_SKILLS_ROOT/wiki" "$SKILL_LINK" "$wiki_agents_status"
  print_export_summary "$GEMINI_SKILLS_ROOT/wiki" "$SKILL_LINK" "$wiki_gemini_status"
  if [ "$doc_extract_present" -eq 1 ]; then
    print_export_summary "$AGENTS_SKILLS_ROOT/doc-extract" "$DOC_EXTRACT_LINK" "$doc_agents_status"
    print_export_summary "$GEMINI_SKILLS_ROOT/doc-extract" "$DOC_EXTRACT_LINK" "$doc_gemini_status"
  else
    echo "  $DOC_EXTRACT_LINK — optional doc-extract canonical не знайдено; exports пропущено"
  fi
  if [ "$any_skipped" -eq 1 ]; then
    echo ""
    echo "Увага: частину exports пропущено через конфлікти. Повідомлення вище показують фактичні шляхи."
    return 2
  fi
  return 0
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

mkdir -p "$SKILLS_ROOT"

# 1. Wiki skill — користувацький pin (за замовчуванням master)
install_skill_at_ref "wiki" "$REPO" "$SKILL_DIR" "$SKILL_LINK" "$WIKI_VERSION"

# 2. Cross-agent wiki exports — ~/.claude/skills лишається shared canonical registry.
# Codex uses ~/.agents/skills as its shared user skill path in the current
# Codex skill runtime. Gemini CLI documents ~/.gemini/skills and
# ~/.agents/skills as user-skill discovery locations:
# https://geminicli.com/docs/cli/using-agent-skills/#discovery-tiers
# Лінкуємо на canonical entrypoint, не на realpath, щоб перемикання canonical версії
# автоматично підхоплювали Codex і Gemini.
WIKI_AGENTS_STATUS="ok"
WIKI_GEMINI_STATUS="ok"
DOC_AGENTS_STATUS="ok"
DOC_GEMINI_STATUS="ok"

if ! export_skill_link "wiki" "$SKILL_LINK" "$AGENTS_SKILLS_ROOT/wiki"; then
  WIKI_AGENTS_STATUS="skipped"
fi
if ! export_skill_link "wiki" "$SKILL_LINK" "$GEMINI_SKILLS_ROOT/wiki"; then
  WIKI_GEMINI_STATUS="skipped"
fi

# 3. doc-extract (optional dependency for ingest-binary). It is pinned to a
# known-good commit for reproducible wiki installs; WIKI_DOC_EXTRACT_REF can
# override it when deliberately testing/upgrading the extractor contract.
# Keep wiki available even if this dependency cannot be installed; text/source
# wiki operations still work.
DOC_EXTRACT_INSTALLED=0
if install_skill_at_ref "doc-extract" "$DOC_EXTRACT_REPO" "$DOC_EXTRACT_DIR" "$DOC_EXTRACT_LINK" "$DOC_EXTRACT_REF"; then
  DOC_EXTRACT_INSTALLED=1
  if ! export_skill_link "doc-extract" "$DOC_EXTRACT_LINK" "$AGENTS_SKILLS_ROOT/doc-extract"; then
    DOC_AGENTS_STATUS="skipped"
  fi
  if ! export_skill_link "doc-extract" "$DOC_EXTRACT_LINK" "$GEMINI_SKILLS_ROOT/doc-extract"; then
    DOC_GEMINI_STATUS="skipped"
  fi
else
  echo "Увага: doc-extract не встановлено. Wiki skill працюватиме, але ingest-binary буде недоступний до повторного встановлення."
fi

ANY_SKIPPED=0
for status in "$WIKI_AGENTS_STATUS" "$WIKI_GEMINI_STATUS" "$DOC_AGENTS_STATUS" "$DOC_GEMINI_STATUS"; do
  [ "$status" = "skipped" ] && ANY_SKIPPED=1
done

echo ""
echo "Готово! Встановлено:"
echo "  $SKILL_LINK → $SKILL_DIR  (@ $WIKI_VERSION)"
echo "  Примітка: ~/.claude/skills — це shared canonical registry; Claude Code не потрібен."
echo "Cross-agent exports (symlinks to shared canonical):"
print_export_summary "$AGENTS_SKILLS_ROOT/wiki" "$SKILL_LINK" "$WIKI_AGENTS_STATUS"
print_export_summary "$GEMINI_SKILLS_ROOT/wiki" "$SKILL_LINK" "$WIKI_GEMINI_STATUS"
if [ "$DOC_EXTRACT_INSTALLED" -eq 1 ]; then
  echo "  $DOC_EXTRACT_LINK → $DOC_EXTRACT_DIR  (@ $DOC_EXTRACT_REF)"
  print_export_summary "$AGENTS_SKILLS_ROOT/doc-extract" "$DOC_EXTRACT_LINK" "$DOC_AGENTS_STATUS"
  print_export_summary "$GEMINI_SKILLS_ROOT/doc-extract" "$DOC_EXTRACT_LINK" "$DOC_GEMINI_STATUS"
fi
if [ "$ANY_SKIPPED" -eq 1 ]; then
  echo ""
  echo "Увага: частину exports пропущено. Summary вище показує фактичний стан кожного шляху —"
  echo "Codex/Gemini бачитимуть лише ті exports, які реально існують і ведуть на canonical."
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
