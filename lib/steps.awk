# The steps of a task file, as data — shared by task-step.sh, step-budget.sh
# and plan-check.sh so the three agree on what a step is.
#
# A step is a line "N. [ ] title" or "N. [x] title" under the "## Steps"
# heading, outside fenced code, with the indented lines beneath it. The same
# shape anywhere else — a template in the design section, an example in a code
# block — is not a step. A file with no "## Steps" heading at all is scanned
# whole (the caller passes -v anywhere=1).
#
# "N. [ ] title" is what /dev-plan is told to write, and a local model writes
# it a little differently each time: "Step 1. [ ] title", "#### Step 1. [ ]",
# "**1.** title", "### Step 3 — title", "5) title", "step 7: title", "Крок 8."
# Two plans in one week were invisible for the word "Step" alone, so the header
# is read loosely: optional heading marks, optional bold, an optional Step/Крок
# word, the number, then ".", ":" or ")" (or just a space after a heading or
# the Step word), an optional [ ]/[x], an optional dash, the title. A number
# alone on a plain line ("3 files changed", "1.5 ratio", "2026-09-11") is not a
# step. What is written back is still the canonical shape.
#
#   awk -v mode=list                      -f steps.awk file → "N|x|title" per step (x, or a space)
#   awk -v mode=block -v n=3              -f steps.awk file → the lines of step 3
#   awk -v mode=paths -v n=3 [-v kinds="Modify Test"] -f steps.awk file
#                                                       → "Kind|path|symbol" per path in those lines
#   awk -v mode=lineno -v n=3             -f steps.awk file → the line number of step 3's header
#
# Paths come from the "- Create:", "- Modify:" and "- Test:" lines: items are
# split at top-level commas (a comma inside parentheses does not split), the
# first word of each item is the path with its ":lines" suffix and trailing
# punctuation cut, and a single-word "(symbol)" beside it is the symbol. A word
# with no slash and no extension, a slash command, "none", or anything quoted is
# prose, not a path.

BEGIN {
  if (mode == "") mode = "list"
  if (kinds == "") kinds = "Create Modify Test"
  nk = split(kinds, kind_list, " ")
  for (k = 1; k <= nk; k++) is_kind[kind_list[k]] = 1
  insteps = anywhere + 0
}

function split_top(s, parts,   i, c, depth, cur, np) {
  np = 0; cur = ""; depth = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "(") depth++
    else if (c == ")") depth--
    if (c == "," && depth <= 0) { parts[++np] = cur; cur = "" }
    else cur = cur c
  }
  parts[++np] = cur
  return np
}

function emit(kind, line,   parts, np, i, chunk, tok, sym) {
  np = split_top(line, parts)
  for (i = 1; i <= np; i++) {
    chunk = parts[i]
    sym = ""
    if (match(chunk, /\([A-Za-z_][A-Za-z0-9_.-]*\)/)) sym = substr(chunk, RSTART + 1, RLENGTH - 2)
    gsub(/`/, "", chunk); sub(/^[[:space:]]+/, "", chunk)
    tok = chunk; sub(/[[:space:]].*$/, "", tok)
    sub(/:[0-9][0-9,-]*$/, "", tok); sub(/:.*$/, "", tok)
    sub(/[;:,.)]+$/, "", tok)
    if (tok == "" || tok == "none") continue
    if (tok ~ /["']/) continue
    if (tok !~ /\// && tok !~ /\.[A-Za-z0-9]+$/) continue
    if (tok ~ /^\/[^\/]*$/) continue
    print kind "|" tok "|" sym
  }
}

# Reads a step header into num, status and title. Returns 1 for a step, 0 for
# anything else. See the shapes in the header comment.
function parse_header(line,   s, loose, i) {
  s = line; loose = 0
  if (sub(/^#+[[:space:]]+/, "", s)) loose = 1
  sub(/^\*\*[[:space:]]*/, "", s)
  if (sub(/^([Ss][Tt][Ee][Pp]|Крок|крок)[[:space:]]+/, "", s)) loose = 1
  if (s !~ /^[0-9]+/) return 0
  match(s, /^[0-9]+/); num = substr(s, 1, RLENGTH); s = substr(s, RLENGTH + 1)
  # After the number: ".", ":" or ")" then a break — or, after a heading mark or
  # the Step word, whitespace or the end is enough.
  if (s ~ /^[.:)]([[:space:]]|\*\*|\[|$)/) sub(/^[.:)]/, "", s)
  else if (!(loose && (s == "" || s ~ /^[[:space:]]/))) return 0
  status = " "
  for (i = 0; i < 4; i++) {
    sub(/^[[:space:]]+/, "", s)
    if (s ~ /^\*\*/) sub(/^\*\*/, "", s)
    else if (s ~ /^\[[ xX]\]/) { if (s ~ /^\[[xX]\]/) status = "x"; sub(/^\[[ xX]\]/, "", s) }
    else if (s ~ /^[—–-]([[:space:]]|$)/) sub(/^[—–-]/, "", s)
    else break
  }
  sub(/^[[:space:]]+/, "", s); title = s
  gsub(/\*\*/, "", title); sub(/[[:space:]]*:[[:space:]]*$/, "", title); sub(/[[:space:]]+$/, "", title)
  return 1
}

# "## Step 3 …" is a step written as a heading, not the end of the ## Steps section.
/^## / && !parse_header($0) { insteps = (anywhere + 0) || ($0 == "## Steps"); on = 0; next }
/^```/ { if (insteps) fence = !fence; next }
!insteps || fence { next }

{
  if (parse_header($0)) {
    if (mode == "list") {
      print num "|" status "|" title
      next
    }
    if (mode == "lineno") { if (num == n) { print NR; exit }; next }
    on = (num == n)
    cur_kind = ""
    if (num != n) next
  }
}
/^<!--/ { on = 0 }
!on { next }

mode == "block" { print; next }
mode == "paths" {
  line = $0
  # A label line: "- Create:", "- **Create**:", "- **Create:**", "Test:" …
  if (match(line, /^[[:space:]]*-?[[:space:]]*(\*{2})?([A-Za-z]+)(\*{2})?:(\*{2})?/)) {
    label = substr(line, RSTART, RLENGTH)
    sub(/^[[:space:]]*-?[[:space:]]*(\*{2})?/, "", label)
    sub(/(\*{2})?:.*/, "", label)
    if (is_kind[label]) {
      cur_kind = label
      sub(/^[[:space:]]*-?[[:space:]]*(\*{2})?[A-Za-z]+(\*{2})?:(\*{2})?[[:space:]]*/, "", line)
      if (line ~ /[^[:space:]]/) emit(cur_kind, line)
    } else {
      cur_kind = ""
    }
    next
  }
  # Sub-bullet under active kind (e.g. "  - `path`")
  if (cur_kind != "" && line ~ /^[[:space:]]+-[[:space:]]+/) {
    sub(/^[[:space:]]+-[[:space:]]+/, "", line)
    emit(cur_kind, line)
  } else if (line !~ /^[[:space:]]*$/) {
    cur_kind = ""
  }
}
