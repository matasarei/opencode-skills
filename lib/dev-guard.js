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

import { existsSync, statSync, readFileSync } from "node:fs"
import { join, dirname } from "node:path"

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
// Local models frequently search for namespaces, Windows paths, or strings containing backslashes
// (e.g. "App\Models\User" or "C:\Path\To\File") without double-escaping for ripgrep's Rust regex engine.
// Rust regex throws fatal "unrecognized escape sequence" on unescaped backslashes, causing infinite retry loops.
function sanitizeGrepPattern(pattern) {
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

// Sanitizes glob path arguments.
// Local models frequently pass a file path (e.g. "src/components/Header.tsx") instead of a
// directory to glob("*.tsx"), causing OpenCode to crash with "glob path must be a directory: ...".
// If the target path is a file (or has a file extension whose parent exists), resolve to its parent directory.
function sanitizeGlobPath(targetPath) {
  if (typeof targetPath !== "string" || !targetPath) return targetPath
  try {
    if (existsSync(targetPath) && statSync(targetPath).isFile()) {
      return dirname(targetPath)
    }
    if (!existsSync(targetPath) && /\.[a-zA-Z0-9]{1,8}$/.test(targetPath)) {
      const parent = dirname(targetPath)
      if (existsSync(parent) && statSync(parent).isDirectory()) {
        return parent
      }
    }
  } catch {}
  return targetPath
}

// Sanitizes bash timeout arguments.
// Local models frequently pass timeouts in seconds (e.g. timeout: 5, timeout: 10, timeout: 30)
// thinking the parameter is in seconds, while OpenCode expects milliseconds.
// A timeout of 5 ms kills the command immediately (often before process spawn finishes).
// Any timeout < 1000 ms is converted to milliseconds (* 1000).
// In addition, enforce a safe minimum (at least 30,000 ms = 30s) so heavy commands like grep/tests don't abort prematurely.
// If timeout is <= 0 or not a finite number, return undefined so OpenCode uses its default (120,000 ms).
function sanitizeBashTimeout(timeout) {
  if (typeof timeout !== "number" || !Number.isFinite(timeout) || timeout <= 0) {
    return undefined
  }
  let ms = timeout < 1000 ? timeout * 1000 : timeout
  if (ms < 30000) {
    ms = 30000
  }
  return ms
}

// Tracks recent tool invocations to detect and abort infinite retry loops.
const callHistory = []

function checkConsecutiveCalls(tool, args) {
  const sig = JSON.stringify({ tool, args })
  callHistory.push(sig)
  if (callHistory.length > 20) callHistory.shift()
  let count = 0
  for (let i = callHistory.length - 1; i >= 0; i--) {
    if (callHistory[i] === sig) count++
    else break
  }
  return count
}

export const DevGuard = async ({ directory }) => {
  const bases = baseBranches(directory || process.cwd())
  return {
    "tool.execute.before": async (input, output) => {
      // 1. Sanitize grep regex patterns to prevent fatal ripgrep crashes on unescaped backslashes
      if (input.tool === "grep" && typeof output?.args?.pattern === "string") {
        output.args.pattern = sanitizeGrepPattern(output.args.pattern)
      }

      // 2. Sanitize glob directory path when a file was mistakenly passed
      if (input.tool === "glob" && output?.args) {
        for (const key of ["path", "dir", "directory", "cwd"]) {
          if (typeof output.args[key] === "string") {
            output.args[key] = sanitizeGlobPath(output.args[key])
          }
        }
      }

      // 3. Prevent reading directories as files (which throws EISDIR)
      if (input.tool === "read" && typeof output?.args?.filePath === "string") {
        try {
          if (existsSync(output.args.filePath) && statSync(output.args.filePath).isDirectory()) {
            throw new Error(
              `dev-guard refuses: "${output.args.filePath}" is a directory, not a file. ` +
              `Use 'glob' or bash 'ls' to inspect its contents, or 'read' a file inside it.`
            )
          }
        } catch (e) {
          if (e.message?.startsWith("dev-guard refuses:")) throw e
        }
      }

      // 4. Normalize line endings to match the target file (CRLF vs LF) to prevent spurious diff explosions
      if (input.tool === "edit" && output?.args && typeof output.args.filePath === "string") {
        try {
          if (existsSync(output.args.filePath)) {
            const content = readFileSync(output.args.filePath, "utf8")
            const isCrlf = content.includes("\r\n")
            if (isCrlf) {
              if (typeof output.args.oldString === "string" && !output.args.oldString.includes("\r\n") && output.args.oldString.includes("\n")) {
                output.args.oldString = output.args.oldString.replace(/\r?\n/g, "\r\n")
              }
              if (typeof output.args.newString === "string" && !output.args.newString.includes("\r\n") && output.args.newString.includes("\n")) {
                output.args.newString = output.args.newString.replace(/\r?\n/g, "\r\n")
              }
            } else {
              if (typeof output.args.oldString === "string" && output.args.oldString.includes("\r\n")) {
                output.args.oldString = output.args.oldString.replace(/\r\n/g, "\n")
              }
              if (typeof output.args.newString === "string" && output.args.newString.includes("\r\n")) {
                output.args.newString = output.args.newString.replace(/\r\n/g, "\n")
              }
            }
          }
        } catch {}
      }

      if (input.tool === "write" && output?.args && typeof output.args.filePath === "string" && typeof output.args.content === "string") {
        try {
          if (existsSync(output.args.filePath)) {
            const existing = readFileSync(output.args.filePath, "utf8")
            if (existing.includes("\r\n") && !output.args.content.includes("\r\n") && output.args.content.includes("\n")) {
              output.args.content = output.args.content.replace(/\r?\n/g, "\r\n")
            }
          }
        } catch {}
      }

      // 5. Prevent infinite edit retry loops on already-updated or mismatched files
      if (input.tool === "edit" && typeof output?.args?.filePath === "string") {
        const repeatCount = checkConsecutiveCalls("edit", output.args)
        if (repeatCount >= 2) {
          const { filePath, newString, oldString } = output.args
          try {
            const content = readFileSync(filePath, "utf8")
            if (typeof newString === "string" && newString && content.includes(newString)) {
              throw new Error(
                `dev-guard refuses: "${newString.trim().slice(0, 80)}" is already present in ${filePath}. ` +
                `This edit has already been applied. Do not retry; move on to the next file or task.`
              )
            }
            if (typeof oldString === "string" && oldString && !content.includes(oldString)) {
              throw new Error(
                `dev-guard refuses: oldString was not found in ${filePath} and this edit call was already attempted. ` +
                `Do not retry the exact same call; read the file with 'read' or 'sed' to verify its actual content, or proceed to the next file.`
              )
            }
          } catch (e) {
            if (e.message?.startsWith("dev-guard refuses:")) throw e
          }
          throw new Error(
            `dev-guard refuses: repeated identical edit call on ${filePath}. ` +
            `The previous call failed. Do not retry the exact same edit; inspect the file first or move on.`
          )
        }
      }

      // 3. General tool call loop breaker (any tool repeated 3x consecutively with identical args)
      if (input.tool !== "edit" && checkConsecutiveCalls(input.tool, output?.args) >= 3) {
        throw new Error(
          `dev-guard refuses: repeated identical tool call detected (3x for ${input.tool}). ` +
          `The previous calls did not produce a new state. Break this loop: inspect the file/environment or move on to the next step.`
        )
      }

      // 4. Sanitize bash/shell timeout argument when model passes seconds instead of milliseconds
      if ((input.tool === "bash" || input.tool === "shell") && output?.args) {
        if ("timeout" in output.args) {
          const sanitized = sanitizeBashTimeout(output.args.timeout)
          if (sanitized !== undefined) {
            output.args.timeout = sanitized
          } else {
            delete output.args.timeout
          }
        }
      }

      // 5. Refuse forbidden bash operations
      if (input.tool !== "bash" && input.tool !== "shell") return
      const reason = reasonToRefuse(output?.args?.command, bases)
      if (reason) throw new Error(`dev-guard refuses: ${reason}`)
    },
  }
}
