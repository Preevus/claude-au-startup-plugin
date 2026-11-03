#!/usr/bin/env bash
# check_repo.sh: checks to run before every commit and push of this marketplace.
#
# Usage: bash scripts/check_repo.sh
#
# Exit status: 0 when every check passes with zero findings, 1 when there is at
# least one finding, 2 when a required tool is missing and the checks cannot run.
#
# Checks, in order:
#   1. Layout: required files exist, and each .claude-plugin/ folder holds only
#      its manifest.
#   2. Manifests: marketplace.json and every plugin.json parse and follow the
#      documented rules.
#   3. Skills: every skills/<folder>/SKILL.md has YAML frontmatter with a name
#      equal to <folder> and a description.
#   4. Skill listing: the README skills table, every plugin.json description and
#      the marketplace.json descriptions list exactly the skills that exist.
#   5. Claude Code validator: claude plugin validate --strict passes for the
#      marketplace, each plugin and each skills folder.
#   6. Forbidden files: real config files, env files, out/, PDFs, HTML,
#      archives and .DS_Store files.
#   7. Personal information and secrets: emails, phone numbers, ABN, ACN, TFN,
#      Director IDs, dates of birth, street addresses, names in form fields, API
#      keys and tokens, workspace links and local file paths. It scans every file
#      that would be committed, the XML inside Office files, the file names and
#      the git commit metadata. Office files must carry no metadata at all (no
#      document properties, revision IDs, thumbnails, real zip timestamps or zip
#      extra fields); scripts/strip_office_metadata.py removes it.
#   8. Style and placeholders: no em dash characters anywhere, and LICENSE names
#      a copyright holder.
#   9. Scripts: shell scripts and Python files parse.
#
# Private search terms (optional, never committed): list words that must never
# appear, such as your own name, email or street, one per line in
# .check-repo-private-terms (git ignores that file), or pass them in
# CHECK_REPO_PRIVATE_TERMS separated by newlines. They are matched as whole
# words, ignoring case. The name and email in your git config are added
# automatically unless they are noreply addresses.
#
# Findings show the matched text so you can judge it. When CI is set (as in
# GitHub Actions) the matched text is masked so public logs never repeat it.
#
# Portable on purpose: bash 3.2 or later, and GNU or BSD (macOS) tools.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd) || exit 2
cd "$ROOT" || exit 2

for tool in jq unzip awk sed grep sort tr wc head cut find; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'check_repo: required tool not found: %s\n' "$tool" >&2
    exit 2
  fi
done

TMP=$(mktemp -d "${TMPDIR:-/tmp}/check_repo.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT

FINDINGS=0
SECTION_START=0
NL='
'
TAB=$(printf '\t')
EMDASH=$(printf '\342\200\224')
PLACEHOLDER='<COPYRIGHT''_HOLDER>'

finding() { # <category> <location> <message>
  FINDINGS=$((FINDINGS + 1))
  printf '  FINDING [%s] %s: %s\n' "$1" "$2" "$3"
}

section() {
  printf '\n== %s ==\n' "$1"
  SECTION_START=$FINDINGS
}

section_end() {
  if [ "$FINDINGS" -eq "$SECTION_START" ]; then
    printf '  ok\n'
  fi
}

reveal() { # print matched text, masked when running in CI
  if [ -n "${CI:-}" ]; then
    printf '%s***' "$(printf '%s' "$1" | cut -c1-2)"
  else
    printf '%s' "$1"
  fi
}

matches() { # <ERE> <text>: true when the text matches
  printf '%s\n' "$2" | grep -E -q -e "$1"
}

# --------------------------------------------------------------------------
section "Files that would be committed"

FILES="$TMP/files"
: > "$FILES"
IN_GIT=0
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IN_GIT=1
  git ls-files -z --cached --others --exclude-standard > "$TMP/files0"
else
  find . -type f ! -path './.git/*' -print0 > "$TMP/files0"
fi
while IFS= read -r -d '' f; do
  f=${f#./}
  case "$f" in
    *"$NL"* | *"$TAB"*)
      finding files "(file name)" "a file name contains a newline or tab"
      continue
      ;;
  esac
  if [ -L "$f" ]; then
    finding files "$f" "symbolic links are not allowed"
    continue
  fi
  [ -f "$f" ] || continue
  printf '%s\n' "$f" >> "$FILES"
done < "$TMP/files0"
sort -o "$FILES" "$FILES"
printf '  %s files\n' "$(wc -l < "$FILES" | tr -d ' ')"
section_end

has_file() { grep -q -x -F -e "$1" "$FILES"; }

# --------------------------------------------------------------------------
section "Layout"

for req in .claude-plugin/marketplace.json README.md LICENSE .gitignore \
  scripts/check_repo.sh scripts/add_skill.sh scripts/strip_office_metadata.py .github/workflows/check.yml; do
  has_file "$req" || finding layout "$req" "required file is missing or ignored by git"
done

while IFS= read -r f; do
  case "$f" in
    .claude-plugin/marketplace.json) ;;
    plugins/*/.claude-plugin/plugin.json)
      rest=${f#plugins/}
      rest=${rest#*/}
      if [ "$rest" != ".claude-plugin/plugin.json" ]; then
        finding layout "$f" "plugin.json belongs at plugins/<plugin>/.claude-plugin/plugin.json"
      fi
      ;;
    .claude-plugin/* | */.claude-plugin/*)
      finding layout "$f" "only marketplace.json (at the root) and plugin.json (in each plugin) belong in a .claude-plugin folder; skills/ and other components go at the plugin root"
      ;;
  esac
done < "$FILES"
section_end

# --------------------------------------------------------------------------
section "Manifests"

MKT=.claude-plugin/marketplace.json
PLUGINS="$TMP/plugins"
: > "$PLUGINS"

if [ ! -f "$MKT" ]; then
  finding manifest "$MKT" "missing"
elif ! jq -e 'type == "object"' "$MKT" >/dev/null 2>&1; then
  finding manifest "$MKT" "is not a valid JSON object"
else
  v=$(jq -r '.name // empty | strings' "$MKT")
  if [ -z "$v" ]; then
    finding manifest "$MKT" "name is missing"
  elif ! matches '^[A-Za-z0-9][A-Za-z0-9._-]*$' "$v" || matches '\.\.' "$v"; then
    finding manifest "$MKT" "name \"$v\" may use only letters, digits, dot, underscore and hyphen, and must start with a letter or digit"
  fi
  [ -n "$(jq -r '.owner.name // empty | strings' "$MKT")" ] ||
    finding manifest "$MKT" "owner.name is required"
  [ -n "$(jq -r '.description // empty | strings' "$MKT")" ] ||
    finding manifest "$MKT" "description is missing"
  if [ "$(jq -r '.plugins | if type == "array" then length else 0 end' "$MKT")" -eq 0 ]; then
    finding manifest "$MKT" "plugins must be a non-empty array"
  fi
  jq -r '.plugins | if type == "array" then .[] else empty end
    | [ (.name // "" | tostring),
        (if (.source | type) == "string" then .source else "(not a string)" end),
        (has("version") | tostring) ] | @tsv' "$MKT" > "$TMP/entries"
  while IFS="$TAB" read -r pname psrc phasver; do
    loc="$MKT (plugin $pname)"
    if ! matches '^[a-z0-9]+(-[a-z0-9]+)*$' "$pname"; then
      finding manifest "$loc" "plugin name must be kebab-case: lowercase letters, digits and single hyphens"
      continue
    fi
    if grep -q -x -F -e "$pname" "$PLUGINS"; then
      finding manifest "$loc" "duplicate plugin name"
      continue
    fi
    printf '%s\n' "$pname" >> "$PLUGINS"
    [ "$psrc" = "./plugins/$pname" ] ||
      finding manifest "$loc" "source must be \"./plugins/$pname\" (found \"$psrc\")"
    [ -d "plugins/$pname" ] || finding manifest "$loc" "folder plugins/$pname does not exist"
    [ "$phasver" = false ] ||
      finding manifest "$loc" "set version only in plugin.json, not in the marketplace entry"
  done < "$TMP/entries"
fi

while IFS= read -r p; do
  pj="plugins/$p/.claude-plugin/plugin.json"
  if [ ! -f "$pj" ]; then
    finding manifest "$pj" "missing"
    continue
  fi
  if ! jq -e 'type == "object"' "$pj" >/dev/null 2>&1; then
    finding manifest "$pj" "is not a valid JSON object"
    continue
  fi
  n=$(jq -r '.name // empty | strings' "$pj")
  [ "$n" = "$p" ] || finding manifest "$pj" "name \"$n\" must equal the marketplace entry name \"$p\""
  case "$n" in
    claude-* | anthropic-* | anthropics-* | cc-plugin-* | claude | anthropic | anthropics)
      finding manifest "$pj" "name \"$n\" is reserved for Anthropic plugins; name it for what it does"
      ;;
  esac
  v=$(jq -r '.version // empty | strings' "$pj")
  matches '^[0-9]+\.[0-9]+\.[0-9]+$' "$v" ||
    finding manifest "$pj" "version must look like 1.2.3 (found \"$v\")"
  [ -n "$(jq -r '.description // empty | strings' "$pj")" ] ||
    finding manifest "$pj" "description is missing"
  [ -n "$(jq -r '.author.name // empty | strings' "$pj")" ] ||
    finding manifest "$pj" "author.name is missing"
  [ "$(jq -r '.license // empty | strings' "$pj")" = MIT ] ||
    finding manifest "$pj" "license must be MIT to match LICENSE"
done < "$PLUGINS"

sed -n 's#^plugins/\([^/]*\)/.*#\1#p' "$FILES" | sort -u > "$TMP/plugin_dirs"
while IFS= read -r d; do
  grep -q -x -F -e "$d" "$PLUGINS" || finding manifest "plugins/$d" "folder is not listed in $MKT"
done < "$TMP/plugin_dirs"
section_end

# --------------------------------------------------------------------------
section "Skills"

fm_value() { # <key> <file>: print a top-level frontmatter value on one line
  awk -v key="$1" -v q="'" '
    NR == 1 { next }
    { sub(/\r$/, "") }
    /^---[[:space:]]*$/ { exit }
    grab {
      if ($0 ~ /^[[:space:]]+[^[:space:]]/ || $0 ~ /^[[:space:]]*$/) {
        t = $0
        sub(/^[[:space:]]+/, "", t)
        if (t != "") v = (v == "" ? t : v " " t)
        next
      }
      grab = 0
    }
    index($0, key ":") == 1 {
      v = substr($0, length(key) + 2)
      sub(/^[[:space:]]+/, "", v)
      sub(/[[:space:]]+$/, "", v)
      if (v ~ /^[|>][-+0-9]*$/) v = ""
      grab = 1
      found = 1
    }
    END {
      if (!found) exit 1
      f = substr(v, 1, 1)
      l = substr(v, length(v), 1)
      if (length(v) >= 2 && ((f == "\"" && l == "\"") || (f == q && l == q)))
        v = substr(v, 2, length(v) - 2)
      print v
    }' "$2"
}

SKILLS="$TMP/skills" # lines: plugin<TAB>skill
: > "$SKILLS"
while IFS= read -r f; do
  case "$f" in
    plugins/*/skills/*)
      p=${f#plugins/}
      p=${p%%/*}
      rest=${f#plugins/"$p"/skills/}
      case "$rest" in
        */*) printf '%s\t%s\n' "$p" "${rest%%/*}" >> "$SKILLS" ;;
        *) finding skills "$f" "files directly in skills/ are not loaded; each skill needs its own folder" ;;
      esac
      ;;
  esac
done < "$FILES"
sort -u -o "$SKILLS" "$SKILLS"

while IFS="$TAB" read -r p s; do
  dir="plugins/$p/skills/$s"
  md="$dir/SKILL.md"
  matches '^[a-z0-9]+(-[a-z0-9]+)*$' "$s" ||
    finding skills "$dir" "folder name must be lowercase letters, digits and single hyphens"
  [ "${#s}" -le 64 ] || finding skills "$dir" "folder name is longer than 64 characters"
  case "$s" in
    *claude* | *anthropic*)
      finding skills "$dir" "skill names cannot contain the reserved words claude or anthropic"
      ;;
  esac
  if ! has_file "$md"; then
    finding skills "$dir" "SKILL.md is missing (the file name must be exactly SKILL.md)"
    continue
  fi
  if [ "$(head -n 1 "$md" | tr -d '\r')" != "---" ]; then
    finding skills "$md" "the first line must be --- to open the YAML frontmatter"
    continue
  fi
  if ! awk 'NR > 1 && /^---[[:space:]]*$/ { found = 1; exit } END { exit !found }' "$md"; then
    finding skills "$md" "the frontmatter is not closed with a --- line"
    continue
  fi
  name=$(fm_value name "$md")
  if [ -z "$name" ]; then
    finding skills "$md" "frontmatter has no name"
  elif [ "$name" != "$s" ]; then
    finding skills "$md" "frontmatter name \"$name\" must equal the folder name \"$s\""
  fi
  desc=$(fm_value description "$md")
  if [ -z "$desc" ]; then
    finding skills "$md" "frontmatter has no description"
  else
    # count UTF-8 characters, not bytes
    dlen=$(printf '%s' "$desc" | tr -d '\200-\277' | wc -c | tr -d ' ')
    [ "$dlen" -le 1024 ] ||
      finding skills "$md" "description is $dlen characters; the limit for Claude skills is 1024"
    if matches '<[A-Za-z/][^>]*>' "$desc"; then
      finding skills "$md" "description must not contain XML tags"
    fi
  fi
done < "$SKILLS"
section_end

# --------------------------------------------------------------------------
section "Skill listing (README, plugin.json, marketplace.json)"

START_MARK='<!-- skills-table:start -->'
END_MARK='<!-- skills-table:end -->'
TABLE="$TMP/table" # lines: skill<TAB>what it does, in README order
: > "$TABLE"
if [ -f README.md ] && grep -q -F -e "$START_MARK" README.md && grep -q -F -e "$END_MARK" README.md; then
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
    }' README.md > "$TABLE"
else
  finding listing README.md "the skills table markers $START_MARK and $END_MARK are missing"
fi

cut -f1 "$TABLE" > "$TMP/table_names"
cut -f2 "$SKILLS" > "$TMP/skill_names"
while IFS="$TAB" read -r s what; do
  [ -n "$what" ] || finding listing "README.md ($s)" "the What it does cell is empty"
  if [ "$(grep -c -x -F -e "$s" "$TMP/table_names")" -gt 1 ]; then
    finding listing "README.md ($s)" "listed more than once"
  fi
  grep -q -x -F -e "$s" "$TMP/skill_names" ||
    finding listing "README.md ($s)" "listed in the README table, but there is no skills/$s folder in any plugin"
done < "$TABLE"
while IFS="$TAB" read -r p s; do
  grep -q -x -F -e "$s" "$TMP/table_names" ||
    finding listing "plugins/$p/skills/$s" "not listed in the README skills table (add a row like | \`$s\` | What it does |)"
done < "$SKILLS"

expected_list() { # <plugin, or empty for all>: "[skill] what" for each row, in README order
  awk -F "$TAB" -v want="$1" -v sf="$SKILLS" '
    BEGIN { while ((getline l < sf) > 0) { split(l, a, "\t"); owner[a[2]] = a[1] } }
    want == "" || owner[$1] == want { out = out (out == "" ? "" : " ") "[" $1 "] " $2 }
    END { print out }' "$TABLE"
}

check_desc() { # <location> <actual> <expected list>
  case "$2" in
    *"Included skills: $3") ;;
    *) finding listing "$1" "description must end with: Included skills: $3" ;;
  esac
}

if [ -f "$MKT" ] && jq -e 'type == "object"' "$MKT" >/dev/null 2>&1; then
  check_desc "$MKT (description)" "$(jq -r '.description // ""' "$MKT")" "$(expected_list "")"
  while IFS= read -r p; do
    want=$(expected_list "$p")
    check_desc "$MKT (plugin $p description)" \
      "$(jq -r --arg p "$p" '.plugins[] | select(.name == $p) | .description // ""' "$MKT")" "$want"
    pj="plugins/$p/.claude-plugin/plugin.json"
    if [ -f "$pj" ] && jq -e 'type == "object"' "$pj" >/dev/null 2>&1; then
      check_desc "$pj (description)" "$(jq -r '.description // ""' "$pj")" "$want"
    fi
  done < "$PLUGINS"
fi
section_end

# --------------------------------------------------------------------------
section "Claude Code validator (claude plugin validate --strict)"

run_validate() { # <path>
  if out=$(claude plugin validate --strict "$1" 2>&1); then
    printf '  passed: %s\n' "$1"
  else
    finding validator "$1" "claude plugin validate --strict failed:"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi
}

if command -v claude >/dev/null 2>&1; then
  run_validate .
  while IFS= read -r p; do
    [ -d "plugins/$p" ] && run_validate "plugins/$p"
    [ -d "plugins/$p/skills" ] && run_validate "plugins/$p/skills"
  done < "$PLUGINS"
else
  finding validator "claude" "the Claude Code CLI is not installed, so claude plugin validate could not run; install it with: npm install -g @anthropic-ai/claude-code"
fi
section_end

# --------------------------------------------------------------------------
section "Forbidden files"

while IFS= read -r f; do
  base=${f##*/}
  case "/$f" in
    */out/*) finding forbidden-file "$f" "generated output in out/ must not be committed" ;;
    */__pycache__/*) finding forbidden-file "$f" "Python caches must not be committed" ;;
  esac
  case "$base" in
    example_config.json) ;;
    *config*.json) finding forbidden-file "$f" "real config files must not be committed; keep only assets/example_config.json with placeholders" ;;
    .env | *.env | .env.*) finding forbidden-file "$f" "environment files must not be committed" ;;
    *.pdf | *.PDF) finding forbidden-file "$f" "PDF files must not be committed" ;;
    *.html | *.htm | *.HTML) finding forbidden-file "$f" "generated HTML must not be committed" ;;
    .DS_Store) finding forbidden-file "$f" ".DS_Store files must not be committed" ;;
    .check-repo-private-terms) finding forbidden-file "$f" "the private search terms file must never be committed" ;;
    *.skill | *.zip) finding forbidden-file "$f" "commit the unpacked skill folder, not the archive" ;;
    *.pyc | *.pyo) finding forbidden-file "$f" "compiled Python must not be committed" ;;
  esac
  if [ "$(wc -c < "$f" | tr -d ' ')" -gt 5000000 ]; then
    finding forbidden-file "$f" "larger than 5 MB"
  fi
done < "$FILES"
section_end

# --------------------------------------------------------------------------
section "Personal information and secrets"

# Private terms: optional file or variable, plus the identity in git config.
PRIVATE="$TMP/private_terms"
: > "$PRIVATE"
if [ -f .check-repo-private-terms ]; then
  tr -d '\r' < .check-repo-private-terms | grep -v -E '^[[:space:]]*(#|$)' >> "$PRIVATE"
fi
if [ -n "${CHECK_REPO_PRIVATE_TERMS:-}" ]; then
  printf '%s\n' "$CHECK_REPO_PRIVATE_TERMS" | tr -d '\r' | grep -v -E '^[[:space:]]*$' >> "$PRIVATE"
fi
if [ "$IN_GIT" -eq 1 ]; then
  for v in "$(git config user.name 2>/dev/null)" "$(git config user.email 2>/dev/null)"; do
    case "$v" in
      '' | Claude | claude | *noreply* | github-actions* | 'GitHub Actions' | runner) ;;
      *) printf '%s\n' "$v" >> "$PRIVATE" ;;
    esac
  done
fi
printf '  private search terms: %s\n' "$(wc -l < "$PRIVATE" | tr -d ' ')"

# Contact details
RE_EMAIL='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
OK_EMAIL='(@example\.(com|org|net)|^noreply@anthropic\.com|^noreply@github\.com|@users\.noreply\.github\.com)$'
RE_PHONE_INTL_AU='(\+|00)61[ -]?(\(0\)[ -]?)?[2-478]([ -]?[0-9]){8}'
RE_PHONE_AU='(^|[^0-9+])0[2-478]([ -]?[0-9]){8}([^0-9]|$)'
RE_PHONE_AREA='\(0[2-478]\)[ -]?[0-9]{4}[ -]?[0-9]{4}'
RE_PHONE_1300='(^|[^0-9])1[38]00([ -]?[0-9]){6}([^0-9]|$)'
RE_PHONE_13='(^|[^0-9])13[ -][0-9]{2}[ -][0-9]{2}([^0-9]|$)'
RE_PHONE_INTL='\+[1-9]([ -]?[0-9]){8,14}'
OK_PHONE_INTL='^\+61'
RE_STREET='(^|[^0-9A-Za-z])[0-9]{1,5}[A-Za-z]?(/[0-9]{1,5}[A-Za-z]?)?,? ([A-Z][A-Za-z.-]+ ){1,3}(Street|St|Road|Rd|Avenue|Ave|Drive|Dr|Lane|Ln|Court|Ct|Place|Pl|Crescent|Cres|Parade|Pde|Highway|Hwy|Boulevard|Blvd|Terrace|Tce|Way|Close|Cl|Circuit|Cct|Grove|Square|Sq|Esplanade|Esp|Mall|Quay)\.?([^A-Za-z]|$)'
RE_POBOX='(^|[^A-Za-z])(p\.? ?o\.?|gpo|locked) ?(box|bag) [0-9]+'
RE_POSTCODE='(^|[^A-Za-z])(NSW|VIC|Vic|QLD|Qld|SA|WA|TAS|Tas|NT|ACT),? [0-9]{4}([^0-9]|$)'

# People
RE_DOB_LABEL='(dob|d\.o\.b|date of birth|birth ?date)[^0-9a-z]{0,12}[0-9]'
RE_DATE_NUM='(^|[^0-9])[0-3]?[0-9][/.-][01]?[0-9][/.-](19[0-9][0-9]|200[0-9])([^0-9]|$)'
RE_DATE_ISO='(^|[^0-9])(19[0-9][0-9]|200[0-9])-[01][0-9]-[0-3][0-9]([^0-9]|$)'
RE_DATE_TXT='(^|[^0-9])[0-3]?[0-9](st|nd|rd|th)? (jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?,? (19[0-9][0-9]|200[0-9])([^0-9]|$)'
RE_DATE_TXT_US='(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.? [0-3]?[0-9](st|nd|rd|th)?,? (19[0-9][0-9]|200[0-9])([^0-9]|$)'
RE_NAME_FIELD='(^|[^A-Za-z])(Name|Full name|Full Name|Director|Secretary|Shareholder|Member|Founder|Applicant|Officeholder|Witness|Signed|Signed by|Signature|Attention|Attn|Contact|Prepared by|Author)[ ]*:[ ]*[A-Z][a-z]+[ -][A-Z][a-z-]+'
RE_HONORIFIC='(^|[^A-Za-z])(Mr|Mrs|Ms|Miss|Mx|Dr|Prof)\.? [A-Z][a-z]+'
RE_ID_LABEL='(^|[^A-Za-z])(ABN|ACN|ARBN|ARSN|TFN|Director ID|Tax File Number)[^0-9A-Za-z]{0,12}[0-9]([ ]?[0-9]){6,15}'

# Secrets, workspace links and local paths
RE_SECRET='((^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}|(sk|rk|pk)_(live|test)_[0-9A-Za-z]{10,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|xox[abposr]-[A-Za-z0-9-]{10,}|xapp-[0-9]-[A-Za-z0-9-]{10,}|hooks\.slack\.com/(services|workflows|triggers)/[A-Za-z0-9/_-]{10,}|(AKIA|ASIA)[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|ya29\.[0-9A-Za-z_-]{20,}|lin_(api|oauth)_[A-Za-z0-9]{20,}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)'
RE_SECRET_ASSIGN='(api[_-]?key|apikey|secret|token|passwd|password|client[_-]?secret|access[_-]?key)["'"'"']?[ ]*[:=][ ]*["'"'"'][^"'"'"' ]{12,}["'"'"']'
OK_SECRET_ASSIGN='([<{$]|your|example|placeholder|replace|changeme|xxxx|\*\*\*)'
RE_URL_CRED='[a-z][a-z0-9+.-]*://[^/ :@"]+:[^/ @"]+@'
RE_GOOGLE_ID='(drive|docs)\.google\.com/[^ "'"'"'<>)]*(/d/|/folders/|[?&]id=)[A-Za-z0-9_-]{20,}'
RE_SLACK_WS='[a-z0-9-]+\.slack\.com'
OK_SLACK_WS='^(api|app|hooks|www|status|slack-files|files|edgeapi)\.slack\.com$'
RE_LINEAR_WS='linear\.app/[A-Za-z0-9-]+/(issue|issues|project|projects|team|teams|view|views)'
RE_PATH='(^|[[:space:]"'"'"'=(`])(/home/[A-Za-z0-9._-]+|/Users/[A-Za-z0-9._-]+|/mnt/(user-data|data|skills))|(^|[^A-Za-z0-9])[A-Za-z]:\\[A-Za-z0-9._-]+|file:/{3}'

trim() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

scan() { # <category> <file> <label> <ERE> [grep option] [ERE of allowed matches]
  _cat=$1
  _file=$2
  _label=$3
  _re=$4
  _opt=${5:-}
  _ok=${6:-}
  if [ -n "$_opt" ]; then
    grep -n -o -E "$_opt" -e "$_re" "$_file" > "$TMP/hits" 2>/dev/null || return 0
  else
    grep -n -o -E -e "$_re" "$_file" > "$TMP/hits" 2>/dev/null || return 0
  fi
  while IFS= read -r _hit; do
    _line=${_hit%%:*}
    _val=$(trim "${_hit#*:}")
    if [ -n "$_ok" ]; then
      if [ -n "$_opt" ]; then
        printf '%s\n' "$_val" | grep -E -q "$_opt" -e "$_ok" && continue
      else
        printf '%s\n' "$_val" | grep -E -q -e "$_ok" && continue
      fi
    fi
    finding "$_cat" "$_label:$_line" "$(reveal "$_val")"
  done < "$TMP/hits"
}

# ABN, ACN, TFN and Director ID numbers, confirmed by their check digits.
scan_ids() { # <file> <label>
  grep -n -o -E -e '[0-9]+( [0-9]+)*' "$1" 2>/dev/null | awk '
    function same(d,  t) { t = d; gsub(substr(d, 1, 1), "", t); return t == "" }
    function abn(d,  w, s, i, v) {
      split("10,1,3,5,7,9,11,13,15,17,19", w, ",")
      s = 0
      for (i = 1; i <= 11; i++) { v = substr(d, i, 1) + 0; if (i == 1) v -= 1; s += v * w[i] }
      return s % 89 == 0
    }
    function acn(d,  w, s, i) {
      split("8,7,6,5,4,3,2,1", w, ",")
      s = 0
      for (i = 1; i <= 8; i++) s += substr(d, i, 1) * w[i]
      return (10 - s % 10) % 10 == substr(d, 9, 1) + 0
    }
    function tfn(d,  w, s, i) {
      split("1,4,3,7,5,8,6,9,10", w, ",")
      s = 0
      for (i = 1; i <= 9; i++) s += substr(d, i, 1) * w[i]
      return s % 11 == 0
    }
    {
      c = index($0, ":")
      ln = substr($0, 1, c - 1)
      k = split(substr($0, c + 1), g, " ")
      for (i = 1; i <= k; i++) {
        d = ""
        for (j = i; j <= k; j++) {
          d = d g[j]
          L = length(d)
          if (L > 15) break
          if (same(d)) continue
          if (L == 11 && abn(d)) print ln "\tpossible ABN (check digit valid)\t" d
          if (L == 9 && acn(d)) print ln "\tpossible ACN (check digit valid)\t" d
          if (L == 9 && tfn(d)) print ln "\tpossible TFN (check digit valid)\t" d
          if (L == 15 && substr(d, 1, 3) == "036") print ln "\tpossible Director ID (15 digits starting 036)\t" d
        }
      }
    }' | sort -u > "$TMP/ids"
  while IFS="$TAB" read -r _line _kind _val; do
    finding id-number "$2:$_line" "$_kind: $(reveal "$_val")"
  done < "$TMP/ids"
}

scan_private() { # <file> <label>
  [ -s "$PRIVATE" ] || return 0
  grep -n -o -i -w -F -f "$PRIVATE" "$1" > "$TMP/hits" 2>/dev/null || return 0
  while IFS= read -r _hit; do
    finding private-term "$2:${_hit%%:*}" "$(reveal "${_hit#*:}")"
  done < "$TMP/hits"
}

scan_raw() { # <file> <label>: scanners that also make sense on raw XML
  scan email "$1" "$2" "$RE_EMAIL" "" "$OK_EMAIL"
  scan secret "$1" "$2" "$RE_SECRET"
  scan secret "$1" "$2" "$RE_SECRET_ASSIGN" -i "$OK_SECRET_ASSIGN"
  scan secret "$1" "$2" "$RE_URL_CRED"
  scan workspace-link "$1" "$2" "$RE_GOOGLE_ID"
  scan workspace-link "$1" "$2" "$RE_SLACK_WS" -i "$OK_SLACK_WS"
  scan workspace-link "$1" "$2" "$RE_LINEAR_WS" -i
  scan local-path "$1" "$2" "$RE_PATH"
  scan_private "$1" "$2"
}

scan_all() { # <file> <label>: every scanner, for text files and text from Office files
  scan_raw "$1" "$2"
  scan phone "$1" "$2" "$RE_PHONE_INTL_AU"
  scan phone "$1" "$2" "$RE_PHONE_AU"
  scan phone "$1" "$2" "$RE_PHONE_AREA"
  scan phone "$1" "$2" "$RE_PHONE_1300"
  scan phone "$1" "$2" "$RE_PHONE_13"
  scan phone "$1" "$2" "$RE_PHONE_INTL" "" "$OK_PHONE_INTL"
  scan address "$1" "$2" "$RE_STREET"
  scan address "$1" "$2" "$RE_POBOX" -i
  scan address "$1" "$2" "$RE_POSTCODE"
  scan date-of-birth "$1" "$2" "$RE_DOB_LABEL" -i
  scan date-of-birth "$1" "$2" "$RE_DATE_NUM"
  scan date-of-birth "$1" "$2" "$RE_DATE_ISO"
  scan date-of-birth "$1" "$2" "$RE_DATE_TXT" -i
  scan date-of-birth "$1" "$2" "$RE_DATE_TXT_US" -i
  scan name "$1" "$2" "$RE_NAME_FIELD"
  scan name "$1" "$2" "$RE_HONORIFIC"
  scan id-number "$1" "$2" "$RE_ID_LABEL" -i
  scan_ids "$1" "$2"
}

xml_to_text() { # <mode: body|props>: Office XML on stdin, readable text on stdout
  awk -v mode="$1" '{
    gsub(/<\/(w:p|a:p|si|row|w:tr)>/, "\n")
    gsub(/<(w:br|w:cr)[^>]*\/>/, "\n")
    gsub(/<(w:tab|a:tab)[^>]*\/>/, " ")
    gsub(/<\/(w:tc|c)>/, " ")
    if (mode == "props") gsub(/<\/[^>]*>/, "\n")
    gsub(/<[^>]*>/, "")
    gsub(/&lt;/, "<"); gsub(/&gt;/, ">"); gsub(/&quot;/, "\""); gsub(/&apos;/, "\047")
    gsub(/&amp;/, "\\&")
    print
  }'
}

TEXTS="$TMP/texts" # lines: file<TAB>label, text to run every scanner on
RAWS="$TMP/raws"   # lines: file<TAB>label, raw XML parts of Office files
: > "$TEXTS"
: > "$RAWS"
cp "$FILES" "$TMP/file_names.txt"
printf '%s\t%s\n' "$TMP/file_names.txt" "(file names)" >> "$TEXTS"

n=0
while IFS= read -r f; do
  [ -s "$f" ] || continue
  case "$f" in
    *.docx | *.docm | *.dotx | *.xlsx | *.xlsm | *.pptx | *.pptm) ;;
    *)
      if grep -I -q . "$f" 2>/dev/null; then
        printf '%s\t%s\n' "$f" "$f" >> "$TEXTS"
      else
        finding binary "$f" "binary files cannot be scanned for personal information; only Office files are allowed"
      fi
      continue
      ;;
  esac
  n=$((n + 1))
  d="$TMP/office/$n"
  mkdir -p "$d"
  if ! unzip -tqq "$f" >/dev/null 2>&1; then
    finding office "$f" "cannot be read as an Office (zip) file"
    continue
  fi
  if unzip -Z "$f" 2>/dev/null | grep -q '^l'; then
    finding office "$f" "contains symbolic links"
    continue
  fi
  unzip -qq -o "$f" -d "$d" >/dev/null 2>&1
  (cd "$d" && find . -type f) | sed 's#^\./##' | sort > "$d.entries"
  while IFS= read -r e; do
    case "$e" in
      *.xml | *.rels) printf '%s\t%s\n' "$d/$e" "$f > $e" >> "$RAWS" ;;
      *.bin) finding office "$f" "contains a binary part ($e), such as macros or printer settings; save a clean copy" ;;
      */embeddings/*) finding office "$f" "contains an embedded file ($e); check it by hand or remove it" ;;
      *.jpg | *.jpeg | *.JPG | *.JPEG | *.tif | *.tiff | *.heic | *.HEIC)
        finding office "$f" "contains a photo ($e), which can carry EXIF data such as names or locations"
        ;;
    esac
    case "$e" in
      word/document.xml | word/header*.xml | word/footer*.xml | word/footnotes.xml | word/endnotes.xml | \
        word/comments*.xml | xl/sharedStrings.xml | xl/worksheets/*.xml | ppt/slides/*.xml | ppt/notesSlides/*.xml)
        xml_to_text body < "$d/$e" > "$d/$e.txt"
        printf '%s\t%s\n' "$d/$e.txt" "$f > $e (text)" >> "$TEXTS"
        ;;
      docProps/*.xml | customXml/*.xml)
        xml_to_text props < "$d/$e" > "$d/$e.txt"
        printf '%s\t%s\n' "$d/$e.txt" "$f > $e (text)" >> "$TEXTS"
        ;;
    esac
  done < "$d.entries"
  # Metadata: none is allowed. scripts/strip_office_metadata.py removes all of
  # it, apart from comment and tracked-change authors, which are content.
  fix="fix with: python3 scripts/strip_office_metadata.py '$f'"
  for part in docProps/core.xml docProps/app.xml; do
    [ -f "$d/$part" ] || continue
    props=$(tr -d '\r\n' < "$d/$part" | grep -o -E '<[A-Za-z][A-Za-z0-9._:-]*' | sed 's/^<//' |
      grep -v -x -E 'cp:coreProperties|Properties' | sort -u | tr '\n' ' ')
    [ -z "$props" ] || finding office-metadata "$f > $part" "document properties present: ${props% }; $fix"
  done
  for tag in dc:creator cp:lastModifiedBy Company Manager; do
    val=$(cat "$d/docProps/core.xml" "$d/docProps/app.xml" 2>/dev/null | tr -d '\r\n' |
      sed -n "s#.*<${tag}[^>]*>\([^<]*\)</${tag}>.*#\1#p")
    [ -z "$val" ] || finding office-metadata "$f ($tag)" "$(reveal "$val")"
  done
  if grep -q -x -F -e docProps/custom.xml "$d.entries"; then
    finding office-metadata "$f > docProps/custom.xml" "custom document properties present; $fix"
  fi
  if grep -q -E '^docProps/thumbnail\.' "$d.entries"; then
    finding office-metadata "$f" "has a thumbnail image of its first page; $fix"
  fi
  if grep -q -x -F -e word/people.xml "$d.entries"; then
    finding office-metadata "$f > word/people.xml" "lists the people who commented; delete the comments in Word"
  fi
  if grep -q -E '^customXml/' "$d.entries"; then
    finding office-metadata "$f > customXml/" "custom XML parts often hold hidden metadata; check them by hand or remove them"
  fi
  ids=$(cat "$d"/word/*.xml 2>/dev/null | grep -o -E '(w:rsid[A-Za-z]*|w14:paraId|w14:textId)="' |
    tr -d '="' | sort -u | tr '\n' ' ')
  [ -z "$ids" ] || finding office-metadata "$f" "revision or paragraph IDs present: ${ids% }; $fix"
  if [ -f "$d/word/settings.xml" ]; then
    sets=$(tr -d '\r\n' < "$d/word/settings.xml" |
      grep -o -E '<(w:rsids|w:rsidRoot|w14:docId|w15:docId|w:savePreviewPicture|w:attachedTemplate|w:docVars|w:mailMerge)[ />]' |
      tr -d '<> /' | sort -u | tr '\n' ' ')
    [ -z "$sets" ] || finding office-metadata "$f > word/settings.xml" "settings that hold or create metadata: ${sets% }; $fix"
  fi
  if unzip -Z -T "$f" 2>/dev/null | sed '1,2d;$d' | awk '$7 != "19800101.000000" { bad = 1 } END { exit !bad }'; then
    finding office-metadata "$f" "zip entries keep their real timestamps; $fix"
  fi
  if unzip -Z -v "$f" 2>/dev/null | grep -q -E 'length of extra field: +[1-9]'; then
    finding office-metadata "$f" "zip extra fields present (they can hold the real time and a user ID); $fix"
  fi
  if unzip -Z -v "$f" 2>/dev/null | grep -q -E 'length of file comment: +[1-9]|The zipfile comment is [1-9]'; then
    finding office-metadata "$f" "zip comments present; $fix"
  fi
  cat "$d"/word/*.xml 2>/dev/null | grep -o -E 'w:author="[^"]*"' | sort -u > "$d.authors"
  while IFS= read -r a; do
    finding office-metadata "$f (comment or tracked change)" "$(reveal "$a"); accept or reject the changes and delete the comments in Word"
  done < "$d.authors"
done < "$FILES"

# Git history: author and committer emails, names and commit messages
GITLOG="$TMP/git_history.txt"
if [ "$IN_GIT" -eq 1 ] && git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  # Authors must use a GitHub noreply address (ID+username@users.noreply.github.com).
  # Committers may also be GitHub itself (noreply@github.com), which commits web
  # edits and the pull request merge commits that the workflow checks out.
  git log --format='author %ae%ncommitter %ce' | sort -u > "$TMP/git_emails"
  while IFS=' ' read -r role e; do
    case "$role:$e" in
      *:*@users.noreply.github.com | committer:noreply@github.com) ;;
      *) finding git-metadata "commit history" "$role email $(reveal "$e") is not a GitHub noreply address (ID+username@users.noreply.github.com)" ;;
    esac
  done < "$TMP/git_emails"
  git log --format='%an%n%cn%n%B' > "$GITLOG"
  printf '%s\t%s\n' "$GITLOG" "(git history)" >> "$TEXTS"
fi

while IFS="$TAB" read -r f label; do
  scan_all "$f" "$label"
done < "$TEXTS"
while IFS="$TAB" read -r f label; do
  scan_raw "$f" "$label"
done < "$RAWS"
section_end

# --------------------------------------------------------------------------
section "Style and placeholders"

check_style() { # <file> <label>
  grep -n -F -e "$EMDASH" "$1" 2>/dev/null | cut -d: -f1 > "$TMP/dash"
  grep -n -i -E -e '&(#8212|#x2014|mdash);' "$1" 2>/dev/null | cut -d: -f1 >> "$TMP/dash"
  sort -n -u "$TMP/dash" > "$TMP/dash2"
  while IFS= read -r _line; do
    finding em-dash "$2:$_line" "em dash character; use a comma, colon, full stop or hyphen"
  done < "$TMP/dash2"
  grep -n -F -e "$PLACEHOLDER" "$1" 2>/dev/null | cut -d: -f1 > "$TMP/ph"
  while IFS= read -r _line; do
    finding placeholder "$2:$_line" "unfilled $PLACEHOLDER placeholder"
  done < "$TMP/ph"
}

while IFS="$TAB" read -r f label; do
  case "$label" in
    *" (text)") ;; # Office text is checked through its raw XML below
    *) check_style "$f" "$label" ;;
  esac
done < "$TEXTS"
while IFS="$TAB" read -r f label; do
  check_style "$f" "$label"
done < "$RAWS"

if [ -f LICENSE ]; then
  grep -q '^MIT License' LICENSE || finding license LICENSE "must be the MIT License"
  holder=$(sed -n 's/^Copyright (c) [0-9]\{4\}\(-[0-9]\{4\}\)\{0,1\} \(.*\)$/\2/p' LICENSE | head -n 1)
  if [ -z "$holder" ] || [ "$holder" = "$PLACEHOLDER" ]; then
    finding license LICENSE "needs a line: Copyright (c) <year> <copyright holder>"
  fi
fi
section_end

# --------------------------------------------------------------------------
section "Scripts"

while IFS= read -r f; do
  case "$f" in
    *.sh)
      if ! bash -n "$f" 2> "$TMP/err"; then
        finding scripts "$f" "bash syntax error: $(head -n 1 "$TMP/err")"
      fi
      if [ "$(head -c 2 "$f")" = '#!' ] && [ ! -x "$f" ]; then
        finding scripts "$f" "starts with #! but is not executable (run chmod +x)"
      fi
      ;;
    *.py)
      if command -v python3 >/dev/null 2>&1; then
        if ! python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1], "rb").read(), sys.argv[1])' "$f" 2> "$TMP/err"; then
          finding scripts "$f" "Python syntax error: $(tail -n 1 "$TMP/err")"
        fi
      else
        printf '  note: python3 not found, %s not syntax checked\n' "$f"
      fi
      ;;
  esac
done < "$FILES"

if command -v shellcheck >/dev/null 2>&1; then
  grep -E '\.sh$' "$FILES" > "$TMP/shfiles"
  while IFS= read -r f; do
    if ! shellcheck -x "$f" > "$TMP/sc" 2>&1; then
      finding scripts "$f" "shellcheck reported problems:"
      sed 's/^/      /' "$TMP/sc"
    fi
  done < "$TMP/shfiles"
else
  printf '  note: shellcheck not installed here, skipped (the GitHub workflow runs it)\n'
fi
section_end

# --------------------------------------------------------------------------
printf '\n'
if [ "$FINDINGS" -eq 0 ]; then
  printf 'All checks passed: 0 findings.\n'
  exit 0
fi
printf '%s finding(s). Fix each one, or ask the repository owner to decide, before you commit or push.\n' "$FINDINGS"
exit 1
