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

/^## / { insteps = (anywhere + 0) || ($0 == "## Steps"); on = 0; next }
/^```/ { if (insteps) fence = !fence; next }
!insteps || fence { next }

/^[0-9]+\. \[[ x]\]/ {
  num = $1; sub(/\.$/, "", num)
  if (mode == "list") {
    title = $0; sub(/^[0-9]+\. \[[ x]\][[:space:]]*/, "", title)
    print num "|" (($0 ~ /^[0-9]+\. \[x\]/) ? "x" : " ") "|" title
    next
  }
  on = (num == n)
}
/^<!--/ { on = 0 }
!on { next }

mode == "block" { print; next }
mode == "paths" {
  for (k = 1; k <= nk; k++) {
    pre = "^[[:space:]]+- " kind_list[k] ":"
    if ($0 ~ pre) { line = $0; sub(pre "[[:space:]]*", "", line); emit(kind_list[k], line) }
  }
}
