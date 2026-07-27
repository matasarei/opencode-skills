## Python conventions

### Style

- **PEP 8**, 4 spaces, and whatever formatter the project already uses — match it rather than
  introducing a second one.
- **Type hints** on function signatures, including the return type. `Optional[X]` is explicit,
  never implied by a `None` default.
- f-strings for interpolation; never `%` or `.format()` in new code, and **never** an f-string
  to build SQL.
- Module-level names are `snake_case`, classes `PascalCase`, constants `UPPER_SNAKE`.
- Prefer specific exceptions over bare `except:` — a bare except swallows `KeyboardInterrupt`
  and every programming error along with the one you meant to handle.
- Context managers (`with`) for anything that must be closed.
- **Never use a mutable default argument** (`def f(items=[])`) — it is shared across calls and
  the resulting bug is reproducible only in sequence.

### Database

- **Parameterised queries only.** Pass parameters to the driver; never build SQL by
  concatenation or f-string, not even for an integer.
- Use the ORM or query layer the project already has, and iterate large result sets rather than
  loading them whole.

### Security

- **Never `eval()`, `exec()`, or `pickle.loads()` on anything a user can influence.** Pickle is
  arbitrary code execution by design — use JSON for untrusted data.
- **Never build a shell command from user input.** Use `subprocess` with an argument list and
  `shell=False`; if a shell is truly required, the input must be validated against an allowlist.
- **Secrets come from the environment or a secret store**, never from source. Confirm the ignore
  rules cover local env files, and that no credential reaches a log line.
- **Validate uploads by content**, store outside any served directory, and generate the stored
  filename rather than trusting the client's.
- Pin dependencies with hashes where the tooling supports it, and treat a known-vulnerable
  dependency as work rather than backlog.
- `requests` and friends: keep certificate verification on. `verify=False` in committed code is
  a finding.

### Web applications

- **Debug mode off in production.** A debug traceback page is remote code execution in some
  frameworks and an information leak in all of them.
- **CSRF protection on every state-changing route.** Enable the framework's protection rather
  than hand-rolling it.
- Session cookies `HttpOnly`, `Secure`, `SameSite`; rotate the session on login and on privilege
  change.
- **Templates escape by default in Jinja2 and Django — do not defeat it.** `|safe`,
  `Markup(...)` and `mark_safe(...)` disable escaping for that value; each use needs a reason
  that survives review.
- Authorisation is checked in the route handler, not only in the template that draws the link.

### Changing data in bulk

Any script that writes across many rows: **dry-run by default**, **safe to run twice**,
**bounded scope with an expected-row-count assertion** that aborts when reality disagrees, and a
stated recovery path before it runs.

### Tests

- `pytest` with fixtures in `conftest.py` for shared setup.
- Test the error paths, not just the happy one — bad input, missing record, failed write, empty
  result.
- No real clock, no unseeded randomness, no `sleep()` in a test; inject a clock, fix a seed,
  wait on a condition.

