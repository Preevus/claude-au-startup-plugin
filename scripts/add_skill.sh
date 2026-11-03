#!/usr/bin/env bash
# add_skill.sh: add a skill to a plugin in this marketplace.
#
# Usage:
#   scripts/add_skill.sh <skill.skill | skill.zip | skill-folder> "<What it does>" [--plugin <name>] [--no-bump]
#
# Steps:
#   1. Unpacks the archive into a new, empty temporary folder (or copies the
#      folder). Archives with absolute paths, .. paths or symbolic links are
#      refused.
#   2. Finds SKILL.md at the top, or inside a single top folder, which it
#      flattens.
#   3. Reads the name from the SKILL.md frontmatter, strips all metadata from
#      its Office files (scripts/strip_office_metadata.py) and copies the skill
#      to plugins/<plugin>/skills/<name>/, so the folder name equals the name.
#   4. Adds a row to the README skills table, then rewrites the skill list at
#      the end of the plugin.json and marketplace.json descriptions to match.
#   5. Bumps the plugin's minor version (for example 0.1.0 to 0.2.0), because
#      installed copies only update when the version changes. --no-bump skips it.
#   6. Runs scripts/check_repo.sh.
#
# It never commits or pushes. Review the result with git status and git diff.

set -u
LC_ALL=C
export LC_ALL

usage() {
  sed -n '3,4p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'add_skill: %s\n' "$*" >&2
  exit 1
}

SRC=''
WHAT=''
PLUGIN=''
BUMP=1
while [ $# -gt 0 ]; do
  case "$1" in
    --plugin)
      [ $# -ge 2 ] || die "--plugin needs a plugin name"
      PLUGIN=$2
      shift 2
      ;;
    --no-bump)
      BUMP=0
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*) die "unknown option: $1" ;;
    *)
      if [ -z "$SRC" ]; then
        SRC=$1
      elif [ -z "$WHAT" ]; then
        WHAT=$1
      else
        die "too many arguments"
      fi
      shift
      ;;
  esac
done
if [ -z "$SRC" ] || [ -z "$WHAT" ]; then
  usage >&2
  exit 1
fi

# Resolve the source before moving to the repository root.
case "$SRC" in
  /*) ;;
  *) SRC="$PWD/$SRC" ;;
esac

ROOT=$(cd "$(dirname "$0")/.." && pwd) || exit 1
cd "$ROOT" || exit 1

for tool in jq unzip awk sed grep find cp; do
  command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
done

# The text goes into a Markdown table and two JSON descriptions.
EMDASH=$(printf '\342\200\224')
case "$WHAT" in
  *'|'*) die "the What it does text cannot contain the | character" ;;
  *"$EMDASH"*) die "the What it does text cannot contain an em dash" ;;
  *'Included skills:'*) die "the What it does text cannot contain the words Included skills:" ;;
esac
if [ "$(printf '%s' "$WHAT" | wc -l | tr -d ' ')" -ne 0 ]; then
  die "the What it does text must be a single line"
fi

if [ -z "$PLUGIN" ]; then
  count=$(find plugins -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  [ "$count" -eq 1 ] || die "there are $count plugins; choose one with --plugin <name>"
  PLUGIN=$(basename "$(find plugins -mindepth 1 -maxdepth 1 -type d)")
fi
PJ="plugins/$PLUGIN/.claude-plugin/plugin.json"
MKT=.claude-plugin/marketplace.json
[ -f "$PJ" ] || die "no plugin manifest at $PJ"
[ -f "$MKT" ] || die "no marketplace manifest at $MKT"
jq -e --arg p "$PLUGIN" '.plugins[] | select(.name == $p)' "$MKT" >/dev/null 2>&1 ||
  die "plugin $PLUGIN is not listed in $MKT"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/add_skill.XXXXXX") || die "cannot create a temporary folder"
trap 'rm -rf "$WORK"' EXIT
U="$WORK/unpacked"
mkdir "$U"

if [ -d "$SRC" ]; then
  [ -z "$(find "$SRC" -type l)" ] || die "the folder contains symbolic links; remove them first"
  cp -R "$SRC/." "$U/"
elif [ -f "$SRC" ]; then
  unzip -tqq "$SRC" >/dev/null 2>&1 || die "not a valid zip archive: $SRC"
  unzip -Z1 "$SRC" > "$WORK/entries" 2>/dev/null || die "cannot list the archive: $SRC"
  if grep -E -q -e '(^/|^[A-Za-z]:|(^|/)\.\.(/|$)|\\)' "$WORK/entries"; then
    die "the archive has unsafe paths (absolute or ..); refusing to unpack it"
  fi
  if unzip -Z "$SRC" 2>/dev/null | grep -q '^l'; then
    die "the archive contains symbolic links; refusing to unpack it"
  fi
  unzip -qq "$SRC" -d "$U" || die "unzip failed for $SRC"
else
  die "not found: $SRC"
fi
find "$U" -name __MACOSX -type d -prune -exec rm -rf {} +
find "$U" -name .DS_Store -type f -exec rm -f {} +

if [ -f "$U/SKILL.md" ]; then
  SKROOT=$U
else
  entries=$(find "$U" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
  top=$(find "$U" -mindepth 1 -maxdepth 1 -type d)
  if [ "$entries" -ne 1 ] || [ -z "$top" ] || [ ! -f "$top/SKILL.md" ]; then
    die "expected SKILL.md at the top, or a single top folder that holds SKILL.md"
  fi
  SKROOT=$top
fi

[ "$(head -n 1 "$SKROOT/SKILL.md" | tr -d '\r')" = "---" ] ||
  die "SKILL.md must start with a --- line that opens the YAML frontmatter"
NAME=$(awk -v q="'" '
  NR == 1 { next }
  { sub(/\r$/, "") }
  /^---[[:space:]]*$/ { exit }
  index($0, "name:") == 1 {
    v = substr($0, 6)
    sub(/^[[:space:]]+/, "", v)
    sub(/[[:space:]]+$/, "", v)
    f = substr(v, 1, 1)
    l = substr(v, length(v), 1)
    if (length(v) >= 2 && ((f == "\"" && l == "\"") || (f == q && l == q))) v = substr(v, 2, length(v) - 2)
    print v
    exit
  }' "$SKROOT/SKILL.md")
[ -n "$NAME" ] || die "the SKILL.md frontmatter has no name"
printf '%s\n' "$NAME" | grep -E -q -e '^[a-z0-9]+(-[a-z0-9]+)*$' ||
  die "skill name \"$NAME\" must be lowercase letters, digits and single hyphens"
[ "${#NAME}" -le 64 ] || die "skill name \"$NAME\" is longer than 64 characters"

DEST="plugins/$PLUGIN/skills/$NAME"
[ ! -e "$DEST" ] || die "$DEST already exists"

START_MARK='<!-- skills-table:start -->'
END_MARK='<!-- skills-table:end -->'
if ! grep -q -F -e "$START_MARK" README.md || ! grep -q -F -e "$END_MARK" README.md; then
  die "README.md is missing the skills table markers"
fi
ROW="| \`$NAME\` | $WHAT |"
existing=$(awk -v start="$START_MARK" -v end="$END_MARK" -v want="| \`$NAME\` |" '
  index($0, start) { on = 1; next }
  index($0, end) { on = 0 }
  on && index($0, want) == 1 { print }' README.md)
if [ -n "$existing" ] && [ "$existing" != "$ROW" ]; then
  die "README.md already lists $NAME with different text; edit or remove that row first"
fi

# Strip metadata from Office files before they enter the repository.
if [ -n "$(find "$SKROOT" -type f \( -iname '*.docx' -o -iname '*.docm' -o -iname '*.dotx' -o -iname '*.dotm' \
  -o -iname '*.xlsx' -o -iname '*.xlsm' -o -iname '*.xltx' -o -iname '*.pptx' -o -iname '*.pptm' -o -iname '*.potx' \) -print)" ]; then
  command -v python3 >/dev/null 2>&1 || die "python3 is needed to strip metadata from this skill's Office files"
  if ! python3 -I scripts/strip_office_metadata.py "$SKROOT" > "$WORK/strip.log" 2>&1; then
    cat "$WORK/strip.log" >&2
    die "could not strip metadata from the Office files"
  fi
  printf 'Office files (metadata check):\n'
  awk -v p="$SKROOT/" 'index($0, p) == 1 { $0 = substr($0, length(p) + 1) } { print "  " $0 }' "$WORK/strip.log"
fi

# Place the skill.
mkdir -p "plugins/$PLUGIN/skills"
cp -R "$SKROOT" "$DEST"
printf 'Added %s\n' "$DEST"

# Add the README row, unless the identical row is already there.
if [ -z "$existing" ]; then
  ROW="$ROW" awk -v end="$END_MARK" 'index($0, end) { print ENVIRON["ROW"] } { print }' README.md > "$WORK/README.md"
  cat "$WORK/README.md" > README.md
  printf 'Added a row to the README skills table\n'
fi

# Rebuild the skill lists from the README table (README order).
TAB=$(printf '\t')
awk -v tab="$TAB" '
  index($0, "<!-- skills-table:start -->") { on = 1; next }
  index($0, "<!-- skills-table:end -->") { on = 0 }
  on && /^\|[[:space:]]*`[^`]+`[[:space:]]*\|/ {
    line = $0
    sub(/^\|[[:space:]]*`/, "", line)
    name = line
    sub(/`.*/, "", name)
    what = line
    sub(/^[^`]*`[[:space:]]*\|[[:space:]]*/, "", what)
    sub(/[[:space:]]*\|[[:space:]]*$/, "", what)
    print name tab what
  }' README.md > "$WORK/table"

find plugins -path '*/skills/*/SKILL.md' -type f | awk -F/ '{ print $2 "\t" $4 }' | sort -u > "$WORK/skills"

skill_list() { # <plugin, or empty for all>
  awk -F "$TAB" -v want="$1" -v sf="$WORK/skills" '
    BEGIN { while ((getline l < sf) > 0) { split(l, a, "\t"); owner[a[2]] = a[1] } }
    want == "" || owner[$1] == want { out = out (out == "" ? "" : " ") "[" $1 "] " $2 }
    END { print out }' "$WORK/table"
}

ALL=$(skill_list "")
MINE=$(skill_list "$PLUGIN")
SET_LIST='(split("Included skills: ")[0]) + "Included skills: "'

jq --arg l "$MINE" ".description |= ($SET_LIST + \$l)" "$PJ" > "$WORK/plugin.json" ||
  die "could not update $PJ"
cat "$WORK/plugin.json" > "$PJ"
jq --arg all "$ALL" --arg mine "$MINE" --arg p "$PLUGIN" "
  .description |= ($SET_LIST + \$all)
  | .plugins |= map(if .name == \$p then .description |= ($SET_LIST + \$mine) else . end)" "$MKT" > "$WORK/marketplace.json" ||
  die "could not update $MKT"
cat "$WORK/marketplace.json" > "$MKT"
printf 'Updated the skill lists in %s and %s\n' "$PJ" "$MKT"

if [ "$BUMP" -eq 1 ]; then
  OLD=$(jq -r '.version // ""' "$PJ")
  printf '%s\n' "$OLD" | grep -E -q -e '^[0-9]+\.[0-9]+\.[0-9]+$' ||
    die "version in $PJ is \"$OLD\"; set it to a value like 0.1.0, then bump it by hand"
  NEW=$(printf '%s\n' "$OLD" | awk -F. '{ printf "%d.%d.0", $1, $2 + 1 }')
  jq --arg v "$NEW" '.version = $v' "$PJ" > "$WORK/plugin.json" && cat "$WORK/plugin.json" > "$PJ"
  printf 'Bumped %s from %s to %s\n' "$PJ" "$OLD" "$NEW"
fi

# Files that git will not commit (for example a real config file) stay local only.
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ignored=$(find "$DEST" -type f -print | git check-ignore --stdin 2>/dev/null)
  if [ -n "$ignored" ]; then
    printf '\nNote: git ignores these files, so they will not be published:\n'
    printf '%s\n' "$ignored" | sed 's/^/  /'
  fi
fi

printf '\nRunning scripts/check_repo.sh\n'
if bash scripts/check_repo.sh; then
  printf '\nDone. Nothing was committed. Review git status and git diff, then commit and push.\n'
else
  printf '\nThe skill was added, but the checks found problems (see above). Nothing was committed.\n' >&2
  printf 'Fix them, or remove %s and revert README.md and the manifests with git.\n' "$DEST" >&2
  exit 1
fi
