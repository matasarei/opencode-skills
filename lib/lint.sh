#!/usr/bin/env bash
# Lint every changed file using the command from the profile, through exec.prefix.
#
# This is the one mechanical check a review can make, and in a repository with no
# tests and no working CI it is the only thing standing between a parse error and
# a white page in production. It is also the one check that must never be reported
# as having run when it did not.
#
#   lint.sh [base]          every file changed against the base branch
#   lint.sh <file>...       the files given — what /dev-implement and /dev-fix call
#
# Exit 0 clean, 1 failures found, 2 no lint command available.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

[ -f .devskills/profile.json ] || bash "$HERE/profile.sh" >/dev/null 2>&1

LINT="$(sed -n 's/.*"lint"[[:space:]]*:[[:space:]]*"\(.*\)",$/\1/p' .devskills/profile.json 2>/dev/null | head -1 | sed 's/\\"/"/g')"
if [ -z "$LINT" ] || [ "$LINT" = "null" ]; then
  echo "NO LINT COMMAND — this review is unlinted. Say so in the report."
  exit 2
fi

# {file} inside a quoted region cannot be filled safely, in either quote.
#
#   '...{file}...'  "$1" is literal inside single quotes: the inner shell expands
#                   its own unset $1 and lints an empty path, reporting clean.
#   "...{file}..."  the substituted "$1" closes that region and leaves $1 bare,
#                   so the path is word-split and globbed — src/*.php reaches the
#                   linter as whatever it matched, which is another file entirely.
#
# Substituting a quoted path instead is worse still: the quotes close the region
# they are already inside, so 'a;touch X.php' runs. Refuse, rather than report.
#
# Counting one character class is not enough to spot either: an apostrophe inside
# "..." is not a delimiter. Walk the text and track the state.
quote_state() { # quote_state <text> -> none | single | double
  s="$1"; st=none; i=0
  while [ "$i" -lt "${#s}" ]; do
    c="${s:$i:1}"
    case "$st" in
      none)
        case "$c" in
          \\) i=$((i + 1)) ;;
          \') st=single ;;
          \") st=double ;;
        esac ;;
      single) [ "$c" = "'" ] && st=none ;;
      double)
        case "$c" in
          \\) i=$((i + 1)) ;;
          \") st=none ;;
        esac ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$st"
}

case "$LINT" in
  *"{file}"*)
    st="$(quote_state "${LINT%%\{file\}*}")"
    if [ "$st" != none ]; then
      echo "NO LINT COMMAND — {file} sits inside $st quotes in the profile's lint"
      echo "command, so the path cannot be passed safely. This review is unlinted:"
      echo "fix \"lint\" in .devskills/profile.json. Got: $LINT"
      exit 2
    fi
    ;;
esac

# If specific files are given, lint them directly. Otherwise, inspect
# what changed against the base branch using changed.sh.
if [ "$#" -gt 0 ] && [ -f "$1" ]; then
  QUEUE=""
  for f in "$@"; do
    [ -f "$f" ] && QUEUE="${QUEUE:+${QUEUE}
}1 M $f"
  done
else
  if ! QUEUE="$(bash "$HERE/changed.sh" "${1:-}" 2>&1)"; then
    echo "LINT NOT RUN — could not determine what changed:"
    printf '%s\n' "$QUEUE" | head -3
    exit 2
  fi
fi

# A lint command with no {file} placeholder is project-wide — `npm run lint` is
# the common one. Substituting into it changes nothing, so the old loop ran the
# entire project's linter once per changed file: eight files, eight full runs,
# and eight copies of the same failure.
case "$LINT" in
  *"{file}"*) ;;
  *)
    changed_count=$(printf '%s\n' "$QUEUE" | grep -c '[^[:space:]]')
    if out="$(bash -c "$LINT" lint.sh 2>&1)"; then
      echo "lint: clean — project-wide command ran once over $changed_count changed file(s)"
      exit 0
    fi
    echo "LINT FAIL (project-wide command)"
    printf '%s\n' "$out" | head -5
    exit 1 ;;
esac

failed=0
linted=0
while read -r _ status file; do
  [ -z "${file:-}" ] && continue
  [ "$status" = "D" ] && continue
  [ -f "$file" ] || continue
  # Every extension a linter the profile can detect actually handles. The old
  # four meant a Go project got `gofmt -l {file}` from the profile and a
  # "nothing was checked" from here, which reads like a pass.
  case "$file" in
    *.php|*.py|*.js|*.jsx|*.ts|*.tsx|*.vue|*.svelte) ;;
    *.go|*.rs|*.rb|*.java|*.kt|*.kts|*.cs|*.swift|*.scala|*.ex|*.exs) ;;
    *.c|*.h|*.cc|*.cpp|*.hpp|*.m|*.mm|*.sh|*.bash|*.pl|*.lua|*.dart) ;;
    *) continue ;;
  esac

  # The path travels as an argument, never spliced into the string the shell
  # evaluates. git quotes almost nothing printable, so 'a;touch${IFS}PWNED.php'
  # is a path it hands over verbatim — interpolating that into a command and
  # evaluating it runs it, and the run still reports "clean". {file} becomes
  # "$1", and the path arrives as bash -c's first positional parameter.
  # A path starting with a dash is an option to whatever the linter is, so it
  # goes in as ./-name. Paths from changed.sh are always repository-relative.
  arg="$file"
  case "$arg" in -*) arg="./$arg" ;; esac

  cmd="${LINT//\{file\}/\"\$1\"}"
  if ! out="$(bash -c "$cmd" lint.sh "$arg" 2>&1)"; then
    echo "LINT FAIL $file"
    printf '%s\n' "$out" | head -5
    failed=1
  fi
  linted=$((linted+1))
done <<EOF
$QUEUE
EOF

if [ "$failed" -ne 0 ]; then
  exit 1
elif [ "$linted" -eq 0 ]; then
  # Also not a pass. Say which it is rather than implying the linter approved.
  echo "lint: no lintable files among the changes — nothing was checked"
else
  echo "lint: clean across $linted changed file(s)"
fi
exit 0
