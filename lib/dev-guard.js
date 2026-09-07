// dev-guard — an OpenCode plugin that refuses the commands every skill here bans.
//
// The skills say "never --force, never --amend, never --no-verify, never push
// to the base branch, never merge" in prose. A 30B model follows prose most of
// the time; this is for the rest of the time. It runs before every bash tool
// call and throws — which OpenCode treats as a refusal — on:
//
//   git push --force / --force-with-lease / -f
//   git commit --amend
//   --no-verify on any git command
//   git push to main, master, or the profile's baseBranch, in every ref shape
//   gh pr merge, gh pr review --approve, gh release create|edit|delete|upload,
//   gh workflow run|enable|disable, gh api …/merge
//
// Quoted text is blanked first, so a commit message may mention a flag.
// Everything else runs — gh pr create and gh pr ready included, which /dev-pr
// uses on purpose. install.sh puts this in <config>/plugins/; there is no
// per-skill hook in OpenCode, so it is on for every session.
//
// Ported from claude-skills' scripts/guard.sh — MIT, same author — the same
// patterns, as JavaScript, because that is what an OpenCode plugin is.

import { readFileSync } from "node:fs"
import { join } from "node:path"

const SEG = "[^|;&]*" // the rest of one command in a pipeline or chain

// A branch name is a literal here, not a pattern: release.1 must not match release01.
const literal = (s) => s.replace(/[^A-Za-z0-9_/-]/g, "\\$&")

// The profile's base branch, when a profile has been written for this directory.
function baseBranches(directory) {
  const bases = ["main", "master"]
  try {
    const profile = JSON.parse(readFileSync(join(directory, ".devskills", "profile.json"), "utf8"))
    if (typeof profile.baseBranch === "string" && profile.baseBranch && !bases.includes(profile.baseBranch)) {
      bases.push(profile.baseBranch)
    }
  } catch {
    // no profile yet, or not a git repository: main and master still hold
  }
  return bases
}

// The reason to refuse, or null. Exported through the plugin only.
function reasonToRefuse(command, bases) {
  if (typeof command !== "string" || !/\b(git|gh)\b/.test(command)) return null
  // Talk about a flag is not use of it: blank quoted text, keep what is outside.
  const scan = command.replace(/'[^']*'/g, "''").replace(/"[^"]*"/g, '""')
  const has = (re) => new RegExp(re).test(scan)

  if (has(`git${SEG}push${SEG}(--force|--force-with-lease|(^|\\s)-f(\\s|$))`)) {
    return "a forced push rewrites history somebody else may have. Push a new commit instead."
  }
  if (has(`git${SEG}commit${SEG}--amend`)) {
    return "--amend rewrites the last commit. Make a new commit instead."
  }
  if (has(`git${SEG}--no-verify`)) {
    return "--no-verify skips a hook. A failing hook means the code needs fixing."
  }
  if (has(`gh${SEG}pr${SEG}\\smerge(\\s|$)`)) {
    return "merging is where this stops. Open or update the pull request; a person merges it."
  }
  if (has(`gh${SEG}pr${SEG}\\s--approve(\\s|$)`)) {
    return "approving is a reviewer's act. A run that wrote the change cannot also approve it."
  }
  if (has(`gh${SEG}release\\s+(create|edit|delete|upload)(\\s|$)`)) {
    return "a release ships to users. That is a decision a person makes, after the merge."
  }
  if (has(`gh${SEG}workflow\\s+(run|enable|disable)(\\s|$)`)) {
    return "running a workflow reaches CI and whatever it deploys. Ask before triggering it."
  }
  if (has(`gh${SEG}api${SEG}/merge`)) {
    return "that API call merges. Opening the pull request is where this stops."
  }
  for (const b of bases) {
    // After a space or a colon (HEAD:main), with an optional + (itself a force),
    // spelled out or not (refs/heads/main), and ending there.
    if (has(`git${SEG}push${SEG}(\\s|:)\\+?(refs/heads/)?${literal(b)}(\\s|:|$)`)) {
      return `a push to the base branch '${b}'. A change lands through a pull request — /dev-pr opens it.`
    }
  }
  return null
}

// Sanitizes grep regex patterns from local models.
// Local models frequently search for PHP namespaces, Windows paths, or code with backslashes
// (e.g. "Company::class|models\company\.Company") without double-escaping for ripgrep's Rust regex engine.
// Rust regex throws fatal "unrecognized escape sequence" on \c, \m, \o, etc., causing an infinite retry loop.
export function sanitizeGrepPattern(pattern) {
  if (typeof pattern !== "string") return pattern
  // Match single backslash (not preceded by another backslash) followed by an alphanumeric character
  return pattern.replace(/(^|[^\\])\\([a-zA-Z0-9_])/g, (match, prefix, char, offset, fullStr) => {
    // Valid standard Rust regex escapes:
    // Classes: d, D, s, S, w, W
    // Boundaries: b, B, A, z
    // Whitespace/control: a, f, t, n, r, v, 0
    if (/^[dDsSwWbBAzaftnrv0]$/.test(char)) {
      return match
    }
    const after = fullStr.slice(offset + match.length - 1)
    // Hex: \xHH
    if (/^x[0-9a-fA-F]{2}/.test(after)) return match
    // Unicode: \uHHHH or \u{...}
    if (/^u([0-9a-fA-F]{4}|\{[0-9a-fA-F]+\})/.test(after)) return match
    // Unicode category: \p{...} or \P{...}
    if (/^[pP]\{[^}]+\}/.test(after)) return match

    // Anything else is an invalid escape in ripgrep that causes Exit 2.
    // Escape the backslash so ripgrep searches for literal \ + char.
    return prefix + "\\\\" + char
  })
}

export const DevGuard = async ({ directory }) => {
  const bases = baseBranches(directory || process.cwd())
  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool === "grep" && typeof output?.args?.pattern === "string") {
        output.args.pattern = sanitizeGrepPattern(output.args.pattern)
      }
      if (input.tool !== "bash") return
      const reason = reasonToRefuse(output?.args?.command, bases)
      if (reason) throw new Error(`dev-guard refuses: ${reason}`)
    },
  }
}
