#!/usr/bin/env bash
# Behaviour cases for lib/dev-guard.js — run them from anywhere:
#
#   bash evals/guard/cases.sh
#
# Every case is "expected | the command the hook is asked about": 2 refused,
# 0 allowed. The plugin is loaded the way OpenCode loads it — the named export
# called with a directory, the tool.execute.before hook called with the tool
# and its arguments — and a throw is a refusal. The table runs once with no
# profile (main and master are the base branches) and once with a profile
# naming another base branch. Needs node; says so and fails without it.
#
# The table is claude-skills' evals/guard/cases.sh, quotes unescaped — MIT,
# same author.
#
# Exits 0 when every case matches, 1 otherwise, naming each mismatch.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
plugin="$root/lib/dev-guard.js"
[ -f "$plugin" ] || { printf 'no dev-guard.js at %s\n' "$plugin" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { printf 'guard: node is required to run the plugin — not installed\n' >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

cat > "$work/cases.txt" <<'TABLE'
# refused — a forced push, however it is spelled
2|git push --force origin x
2|git push --force-with-lease
2|git push -f origin x
2|cd sub && git push --force
# refused — rewriting or skipping
2|git commit --amend -m "x"
2|git commit --no-verify -m "x"
2|git push --no-verify
# refused — a push to the base branch, in each of its shapes
2|git push origin main
2|git push -u origin master
2|git push origin HEAD:main
2|git push origin master:master
2|git push origin +main
2|git push origin HEAD:refs/heads/main
2|git push origin +refs/heads/master
2|git push --delete origin main
# allowed — an ordinary branch whose name merely contains one
0|git push origin feature/x
0|git push origin feature/main-thing
0|git push origin main-thing
0|git push origin domain
0|git push -u origin step/local-model-step-cycle-8
# allowed — talk about a flag is not use of it
0|git commit -m "never pass --no-verify"
0|git commit -m "push --force is banned here"
0|git commit -m 'do not --amend'
# allowed — and the flags outside the quotes are still seen
2|git commit -m "msg" && git push --force
# refused — the gh commands that end or ship a change
2|gh pr merge 12
2|gh pr merge --squash --delete-branch 12
2|gh pr merge --admin
2|gh pr review 12 --approve
2|gh release create v1.2.0
2|gh release upload v1.2.0 dist.zip
2|gh workflow run deploy.yml
2|gh api repos/o/r/pulls/12/merge -X PUT
# allowed — the gh a skill actually needs, including the ones that say merge
0|gh pr create --base main --head x
0|gh pr ready 12
0|gh pr view 12 --json mergeable,mergeStateStatus
0|gh pr list --search "merge conflict"
0|gh pr comment 12 --body "this needs a merge from main"
0|gh repo view --json isPrivate
0|gh api repos/o/r/pulls/12/comments
# allowed — nothing to do with git, or nothing to read
0|ls -la
0|rm -rf build
TABLE

# The same table with a profile naming another base branch: it is refused too,
# and main and master still are.
cat > "$work/profile-cases.txt" <<'TABLE'
2|git push origin release
2|git push origin HEAD:release
2|git push origin main
0|git push origin release-notes
0|git push origin feature/release
TABLE
mkdir -p "$work/withprofile/.devskills"
printf '{ "baseBranch": "release" }\n' > "$work/withprofile/.devskills/profile.json"

cat > "$work/run.mjs" <<'JS'
import { readFileSync } from "node:fs"
import { pathToFileURL } from "node:url"
const [pluginPath, casesPath, dir, label] = process.argv.slice(2)
const mod = await import(pathToFileURL(pluginPath).href)
const hooks = await mod.DevGuard({ directory: dir })
const hook = hooks["tool.execute.before"]
let fails = 0
for (const line of readFileSync(casesPath, "utf8").split("\n")) {
  if (!line || line.startsWith("#")) continue
  const i = line.indexOf("|")
  const want = line.slice(0, i), cmd = line.slice(i + 1)
  let got = "0", reason = ""
  try { await hook({ tool: "bash", sessionID: "s" }, { args: { command: cmd } }) }
  catch (e) { got = "2"; reason = e.message }
  if (got !== want) { fails++; console.log(`FAIL  ${label} want=${want} got=${got}  ${cmd}${reason ? "  (" + reason + ")" : ""}`) }
}
// Another tool's arguments are never read: an edit whose text mentions a push is not a push.
try { await hook({ tool: "edit" }, { args: { command: "git push --force" } }) }
catch { fails++; console.log(`FAIL  ${label} a non-bash tool was refused`) }
// Grep patterns with unescaped backslashes (e.g. PHP namespaces) are sanitized
const grepArgs = { pattern: "Company::class|models\\company\\.Company" }
await hook({ tool: "grep" }, { args: grepArgs })
if (grepArgs.pattern !== "Company::class|models\\\\company\\.Company") {
  fails++
  console.log(`FAIL  ${label} grep pattern was not sanitized: ${grepArgs.pattern}`)
}
// Repeated identical edit call on an already-updated file is refused on retry
const dummyFile = `${dir}/dummy.php`
const { writeFileSync } = await import("node:fs")
writeFileSync(dummyFile, "use CompanyBundle\\Entity\\Company;\n")
const editArgs = { filePath: dummyFile, oldString: "use models\\company\\Company;", newString: "use CompanyBundle\\Entity\\Company;" }
await hook({ tool: "edit" }, { args: editArgs })
let editRefused = false
try { await hook({ tool: "edit" }, { args: editArgs }) }
catch (e) { if (e.message.includes("is already present")) editRefused = true }
if (!editRefused) { fails++; console.log(`FAIL  ${label} repeated edit on already-updated file was not refused`) }
process.exit(fails ? 1 : 0)
JS

fails=0
node "$work/run.mjs" "$plugin" "$work/cases.txt" "$work" 'no-profile' || fails=$((fails + 1))
node "$work/run.mjs" "$plugin" "$work/profile-cases.txt" "$work/withprofile" 'profile' || fails=$((fails + 1))

if [ "$fails" -eq 0 ]; then
  printf 'guard: all cases pass\n'
else
  printf 'guard: %s table(s) with failures\n' "$fails" >&2
fi
exit $((fails > 0))
