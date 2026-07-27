## CMS conventions

### The core, and who owns it

**First work out which of these you are in**, because the rules differ and the answer is not
always obvious. Check whether core is in `.gitignore`, whether a package manager declares it,
and whether anyone has written down how the site gets updated.

**A. Core is installed and updated outside the repository** — by a package manager, a CLI tool,
or the host's own updater. Only your themes, plugins and site code are committed. *This is the
common case and the one to aim for.*

Editing core here is pointless as well as wrong: the next update silently reverts it, so the bug
comes back at the worst possible moment and nobody remembers why. Extend through the documented
seams — child theme, plugin, hooks and filters.

**B. Core is committed, and still updated by dropping in new releases.** Editing it means every
update becomes a manual merge, and a patch quietly lost in one of those merges is a
reintroduced bug nobody is looking for. Same conclusion, different reason.

**C. Core is committed and permanently forked** — no update path, no intention of one.

Here you genuinely *can* edit anything; the tree is yours. The cost is not lost work, it is
this: **the update path is also the security path.** Forking core opts you out of upstream
security releases, and a public CMS is scanned continuously for known vulnerabilities in known
versions. Whoever forked it has taken on patching every future CVE by hand, forever, including
the ones announced when they are on holiday.

So the rule in every case is **prefer the hooks** — but for different reasons. In A and B
because the edit will not survive; in C because every line you add to core is a line that makes
returning to a supported version harder, and returning is the goal.

If core has already been forked, treat it as a standing risk rather than a settled decision:
record the version it diverged from, keep the diff against upstream as small and as documented
as possible, and know which advisories apply to that version. Getting back onto a maintained
core is a real piece of work worth scheduling, not a purity exercise.

- **Never edit a third-party plugin or theme in place** — the same three cases apply. Fork it
  properly or override through the provided hooks.
- Keep core, themes and plugins **updated** wherever an update path exists. On a public CMS the
  overwhelming majority of compromises arrive through a known vulnerability in an out-of-date
  component, not through bespoke code. Treat a pending security update as urgent work.
- Remove what is unused. A deactivated-but-installed plugin is still code on disk and still a
  candidate for exploitation.

### Input, output, and the three checks

WordPress-style APIs are named below; the equivalents in another CMS follow the same shape.

- **Sanitise on input.** Never trust `$_GET`, `$_POST`, `$_REQUEST` or `$_COOKIE`. Run each
  through the narrowest sanitiser that fits — `sanitize_text_field()`, `absint()`,
  `sanitize_email()`, `esc_url_raw()`.
- **Escape on output, per context.** `esc_html()` in the body, `esc_attr()` inside an attribute,
  `esc_url()` for links, `wp_kses_post()` where limited markup is genuinely wanted. Escape at
  the point of output, not on the way in — the same value can be safe in one context and an
  injection in another.
- **Nonces on every state-changing action.** `wp_nonce_field()` in the form,
  `check_admin_referer()` or `wp_verify_nonce()` on the handler. A form without one is a
  cross-site request forgery hole.
- **Capabilities, not roles.** `current_user_can('edit_others_posts')` on the action itself.
  Hiding an admin menu entry is not access control; the endpoint remains reachable.
- **`$wpdb->prepare()` for every query with a variable**, including integers. Never concatenate
  into SQL.

Those four — sanitise, escape, nonce, capability — are the checks that get skipped under time
pressure, and each one skipped is a real hole rather than a style lapse.

### Files, uploads and secrets

- Uploads go through the CMS media API, validated by inspecting content rather than the
  supplied name or MIME header.
- Never place executable code in an uploads directory, and ensure that directory cannot execute.
- Credentials and salts live in the configuration file, which is **not committed**. Confirm the
  ignore rules cover it and that it sits outside the web root where the host allows.
- Disable file editing from the admin UI (`DISALLOW_FILE_EDIT`) — it turns any admin account
  compromise into arbitrary code execution.
- Turn display of errors off in production; log instead. A stack trace in a page reveals paths
  and versions.

### Style

- Follow the CMS's own coding standards rather than a general PHP guide — its linter and its
  reviewers assume them.
- Prefix every global function, class, option key and database table with the theme or plugin
  slug. The global namespace is shared with every other plugin on the site, and a collision is
  a hard-to-trace breakage.
- Enqueue scripts and styles properly (`wp_enqueue_script`/`_style`) with declared dependencies
  and a version string. Never hard-code a `<script>` tag into a template.
- Use the CMS's translation functions for user-facing text rather than inline literals.

