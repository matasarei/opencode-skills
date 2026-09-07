# The steps of a task file, as data — shared by task-step.sh, step-budget.sh
# and plan-check.sh so the three agree on what a step is.
#
# A step is a line "N. [ ] title" or "N. [x] title" under the "## Steps"
# heading, outside fenced code, with the indented lines beneath it. The same
# shape anywhere else — a template in the design section, an example in a code
# block — is not a step. A file with no "## Steps" heading at all is scanned
# whole (the caller passes -v anywhere=1).
#
#   awk -v mode=list                      -f steps.awk file → "N|x|title" per step (x, or a space)
#   awk -v mode=block -v n=3              -f steps.awk file → the lines of step 3
#   awk -v mode=paths -v n=3 [-v kinds="Modify Test"] -f steps.awk file
#                                                       → "Kind|path|symbol" per path in those lines
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

function is_step_header(line) {
  if (line ~ /^[0-9]+\. \[[ xX]\]/) return 1
  if (line ~ /^[0-9]+\.[[:space:]]/) return 2
  if (line ~ /^###[[:space:]]+(Step[[:space:]]+)?[0-9]+/) return 3
  return 0
}

/^## / { insteps = (anywhere + 0) || ($0 == "## Steps"); on = 0; next }
/^```/ { if (insteps) fence = !fence; next }
!insteps || fence { next }

{
  m = is_step_header($0)
  if (m > 0) {
    if (m == 1) {
      match($0, /^[0-9]+/)
      num = substr($0, RSTART, RLENGTH)
      status = ($0 ~ /^[0-9]+\. \[[xX]\]/) ? "x" : " "
      title = $0; sub(/^[0-9]+\. \[[ xX]\][[:space:]]*/, "", title)
    } else if (m == 2) {
      match($0, /^[0-9]+/)
      num = substr($0, RSTART, RLENGTH)
      status = ($0 ~ /\[[xX]\]/) ? "x" : " "
      title = $0; sub(/^[0-9]+\.[[:space:]]+/, "", title)
      sub(/^\[[ xX]\][[:space:]]*/, "", title)
      sub(/^\*\*[[:space:]]*/, "", title); sub(/[[:space:]]*\*\*$/, "", title)
    } else if (m == 3) {
      line = $0; sub(/^###[[:space:]]+(Step[[:space:]]+)?/, "", line)
      match(line, /^[0-9]+/)
      num = substr(line, RSTART, RLENGTH)
      status = ($0 ~ /\[[xX]\]/) ? "x" : " "
      title = line; sub(/^[0-9]+[[:space:]]*[:.—–-][[:space:]]*/, "", title)
      sub(/^\[[ xX]\][[:space:]]*/, "", title)
      sub(/^\*\*[[:space:]]*/, "", title); sub(/[[:space:]]*\*\*$/, "", title)
    }
    if (mode == "list") {
      print num "|" status "|" title
      next
    }
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
  # Check if line has a label like - Create:, - **Create:**, - Test:, etc.
  if (match(line, /^[[:space:]]*-?[[:space:]]*(\*{2})?([A-Za-z]+)(\*{2})?:/)) {
    label = substr(line, RSTART, RLENGTH)
    sub(/^[[:space:]]*-?[[:space:]]*(\*{2})?/, "", label)
    sub(/(\*{2})?:.*/, "", label)
    if (is_kind[label]) {
      cur_kind = label
      sub(/^[[:space:]]*-?[[:space:]]*(\*{2})?[A-Za-z]+(\*{2})?:[[:space:]]*/, "", line)
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
