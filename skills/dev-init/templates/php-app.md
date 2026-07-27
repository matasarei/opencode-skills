## PHP conventions

### Style

- `declare(strict_types=1);` at the top of every new file.
- **4 spaces**, Unix line endings, no trailing whitespace, no closing `?>`.
- **Strict comparison** — `===` and `!==`. `==` hides type juggling bugs.
- **Type hints and return types** on everything new, including `void`. Nullable types are
  explicit (`?string`), never implied by a `null` default.
- **`DateTimeImmutable`**, not `DateTime` — a mutable date passed into a method and modified
  there is a bug that reproduces only under specific ordering.
- Short array syntax `[]`. Trailing comma on multi-line arrays and argument lists.
- **Names are words, not abbreviations** — `$entityManager`, not `$em`. Interfaces end in
  `Interface`.
- **Return early.** No `else` after a `return`; no assignments inside conditions.
- Comments explain **why**, never what. A comment restating the code is noise that goes stale.
- Prefer composition over inheritance. Keep models thin — business logic belongs in services,
  and services should not hold request-scoped state.

### Database

- **Placeholders for every variable.** Never interpolate into SQL, not even an integer you
  "know" is safe — the next caller will not know it.
- Prefer the project's repository or mapper API over raw SQL. Where raw SQL is genuinely needed,
  it still uses bound parameters.
- Iterate large result sets rather than loading them whole.
- Watch for **N+1 queries** inside loops over user-scale data.

### Security

Treat every one of these as a blocker, not a preference.

- **Escape at output.** Establish which layer escapes and state it in this file. If the
  templates do **not** escape automatically, then every value interpolated into HTML must be
  escaped at the point of output — `htmlspecialchars($v, ENT_QUOTES, 'UTF-8')` — and the
  reviewer's default assumption must be that an un-escaped echo is a hole.
- **Escape per context.** HTML body, HTML attribute, URL parameter, JavaScript and CSS each need
  different escaping. Putting an un-encoded value into a `<script>` block or an `href` is an
  injection even when the HTML body would have been fine.
- **CSRF on every state-changing request.** A token bound to the session, verified server-side,
  on every POST/PUT/DELETE. If the framework has no helper, that is a gap to fix once in the
  shared layer, not to work around per form.
- **Authorisation on every entry point.** Check the permission where the action happens, not
  only where the link is drawn. Hiding a button is not access control, and an object id in a URL
  is not proof the caller owns that object.
- **Passwords** via `password_hash()` / `password_verify()`. Never a bare hash, never a
  home-made scheme.
- **Sessions**: regenerate the id on login and privilege change; cookies `HttpOnly`, `Secure`
  and `SameSite`.
- **Uploads**: validate by inspecting content, not the client-supplied name or MIME header.
  Store outside the web root, or in a path that cannot execute. Generate the stored filename —
  never reuse what the user sent.
- **Never** `eval()`, `extract()` on request data, `unserialize()` on anything a user can
  influence, or a shell call built from user input.
- **Secrets live in configuration that is not committed.** Confirm the ignore rules actually
  cover them, and that no credential ever reaches a log or an error page.
- **Errors**: log the detail, show the user nothing but a generic message. Stack traces and SQL
  in a response are a disclosure.
- **Exports carry a formula-injection risk** — a spreadsheet cell starting `=`, `+`, `-` or `@`
  executes on open. Write user-controlled text as an explicit string type.

### Changing data in bulk

Any script that writes across many rows:

- **dry-run by default**, applying only behind an explicit flag;
- **safe to run twice** — the second run is a no-op, not a duplicate;
- **bounded scope** and an **expected-row-count assertion** that aborts when reality disagrees;
- a stated recovery path before it runs.

A wrong `WHERE` clause against records of record is not a bug you fix forward.

### Dependencies

- Commit the lock file alongside the manifest, always in the same change.
- Treat an **end-of-life PHP version as a standing security finding**, not a style note — no
  amount of careful code compensates for an interpreter that no longer receives patches.

