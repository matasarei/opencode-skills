#!/usr/bin/env bash
# Detect this repository's toolchain once and cache it as JSON.
#
# Every dev skill starts by running this. It exists so the model never has to
# *decide* how to test, lint or run the project — the answer is computed here,
# deterministically, and handed over as data.
#
#   profile.sh              print the cached profile, detecting it if absent
#   profile.sh --reprofile  discard the cache and detect again
#   profile.sh --path       print the cache path and nothing else
#
# Output is JSON on stdout. A field that does not apply is null, and null is a
# real answer: a repository with no test command must not be given one.

set -u

CACHE=".devskills/profile.json"

case "${1:-}" in
  --path) echo "$CACHE"; exit 0 ;;
  --reprofile) rm -f "$CACHE" ;;
esac

if [ -f "$CACHE" ] && [ "${1:-}" != "--reprofile" ]; then
  cat "$CACHE"
  exit 0
fi

# ---------------------------------------------------------------- helpers ---

# JSON string escape. Enough for paths and commands; these are not arbitrary text.
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'; }

# Emit "key": value — quoted unless the value is literally null/true/false.
kv() {
  case "$2" in
    null|true|false) printf '  "%s": %s' "$1" "$2" ;;
    *) printf '  "%s": "%s"' "$1" "$(esc "$2")" ;;
  esac
}

have() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------- 0 platform ---

case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin) PLATFORM=macos ;;
  Linux)  PLATFORM=linux ;;
  MINGW*|MSYS*|CYGWIN*)
    # Native Windows is not supported. Refusing here is deliberate: under a POSIX
    # translation layer these scripts mostly work, and "mostly" is the problem —
    # container mounts land in the wrong place and a false pass reads like a real
    # one. WSL is a real Linux kernel and needs none of the special cases.
    echo "Native Windows (Git Bash / MSYS / Cygwin) is not supported." >&2
    echo "Run OpenCode inside WSL and install there — everything works as on Linux." >&2
    echo "Keep repositories in the WSL filesystem, not under /mnt/c, or git will be slow." >&2
    exit 78
    ;;
  *) PLATFORM=unknown ;;
esac

# ---------------------------------------------------------- 1 base branch ---

BASE="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's#^refs/remotes/origin/##')"
if [ -z "$BASE" ]; then
  for candidate in main master; do
    if git show-ref --verify --quiet "refs/heads/$candidate" 2>/dev/null; then BASE="$candidate"; break; fi
  done
fi
[ -z "$BASE" ] && BASE="main"

# -------------------------------------------------------- 2 standards doc ---

STANDARDS=null
for f in AGENTS.md CLAUDE.md CONTRIBUTING.md README.md; do
  [ -f "$f" ] && { STANDARDS="$f"; break; }
done

# --------------------------------------------------------------- 3 family ---

FAMILY=other
LANGUAGE=null

if [ -f version.php ] && grep -qs 'plugin->component' version.php; then
  FAMILY=moodle-plugin
elif [ -d wp-content ] || { [ -f functions.php ] && [ -f style.css ]; }; then
  FAMILY=cms
elif [ -f composer.json ] && [ -d application/core ] && [ -f run ]; then
  FAMILY=php-app
elif [ -f composer.json ] && grep -qs '"type"[[:space:]]*:[[:space:]]*"library"' composer.json; then
  FAMILY=php-library
elif [ -f composer.json ] && [ -d src ] && [ -d tests ]; then
  FAMILY=php-library
elif [ -f composer.json ]; then
  FAMILY=php-app
elif [ -f pyproject.toml ] || [ -f requirements.txt ]; then
  FAMILY=python-app
elif [ -f package.json ]; then
  FAMILY=node
fi

# Language and version, read from the project's own declaration rather than the host.
case "$FAMILY" in
  moodle-plugin|cms|php-app|php-library)
    PHPREQ="$(grep -os '"php"[[:space:]]*:[[:space:]]*"[^"]*"' composer.json 2>/dev/null | head -1 | sed 's/.*"php"[[:space:]]*:[[:space:]]*"//; s/"$//')"
    [ -n "$PHPREQ" ] && LANGUAGE="PHP $PHPREQ" || LANGUAGE="PHP"
    ;;
  python-app)
    # Anchor on the opening quote of the value. A bare `s/.*"//` is greedy and eats
    # through the closing quote instead, leaving nothing.
    PYREQ="$(grep -os 'requires-python[[:space:]]*=[[:space:]]*"[^"]*"' pyproject.toml 2>/dev/null | head -1 | sed 's/.*=[[:space:]]*"//; s/"$//')"
    [ -n "$PYREQ" ] && LANGUAGE="Python $PYREQ" || LANGUAGE="Python"
    ;;
  node) LANGUAGE="Node" ;;
esac

# ------------------------------------------------------------------ 4 exec ---
#
# Container first, on every platform — the project targets a specific runtime and
# the host's is often a different one. Host is a fallback, and it is recorded as
# such so a green run against the wrong version is never reported as a pass.

EXEC_KIND=host
EXEC_PREFIX=""
EXEC_NOTE=null

COMPOSE_FILE=""
for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
  [ -f "$f" ] && { COMPOSE_FILE="$f"; break; }
done

docker_up() { have docker && docker info >/dev/null 2>&1; }

if ! docker_up; then
  EXEC_NOTE="Docker not available or daemon not running; falling back to the host toolchain."
elif [ -n "$COMPOSE_FILE" ]; then
  # Prefer a service whose name looks like the application, else the first one.
  SERVICES="$(docker compose config --services 2>/dev/null)"
  SVC=""
  for want in app php web api backend; do
    for s in $SERVICES; do [ "$s" = "$want" ] && { SVC="$s"; break 2; }; done
  done
  [ -z "$SVC" ] && SVC="$(printf '%s\n' "$SERVICES" | head -1)"
  if [ -n "$SVC" ]; then
    EXEC_KIND=compose
    EXEC_PREFIX="docker compose exec -T $SVC"
    if ! docker compose ps --status running 2>/dev/null | grep -qs "$SVC"; then
      EXEC_NOTE="Service '$SVC' is not running; use 'docker compose run --rm $SVC' or start it first."
    fi
  fi
fi

if [ "$EXEC_KIND" = "host" ] && docker_up && [ -z "$COMPOSE_FILE" ]; then
  # No compose file. Infer an image from the language, then PROVE the bind mount
  # works before storing it. A mount can succeed and still be empty — commands
  # then run, find nothing, and report something that looks like a result.
  IMAGE=""
  case "$FAMILY" in
    moodle-plugin|cms|php-app|php-library) IMAGE="composer:lts" ;;
    python-app) IMAGE="python:3-slim" ;;
    node) IMAGE="node:lts-alpine" ;;
  esac
  # Probe with any file we know is here. It must not be the standards doc: that can
  # legitimately be absent, and a repository without one would then never get an
  # image prefix for a reason that has nothing to do with Docker.
  PROBE=""
  for p in "$STANDARDS" composer.json package.json pyproject.toml version.php .gitignore; do
    [ "$p" != "null" ] && [ -f "$p" ] && { PROBE="$p"; break; }
  done

  if [ -n "$IMAGE" ] && [ -n "$PROBE" ]; then
    if docker run --rm -v "${PWD}":/app -w /app "$IMAGE" \
         ls "/app/$PROBE" >/dev/null 2>&1; then
      EXEC_KIND=image
      EXEC_PREFIX="docker run --rm -v \"\${PWD}\":/app -w /app $IMAGE"
    else
      EXEC_NOTE="Bind mount into $IMAGE could not see /app/$PROBE — the daemon is probably remote. Using the host."
    fi
  fi
fi

if [ "$EXEC_KIND" = "host" ] && [ "$EXEC_NOTE" = "null" ]; then
  EXEC_NOTE="No container runtime resolved; commands run against this machine's toolchain, which may not be the version the project targets."
fi

# Wrap a project command in the resolved prefix.
wrap() { [ -n "$EXEC_PREFIX" ] && printf '%s %s' "$EXEC_PREFIX" "$1" || printf '%s' "$1"; }

# ------------------------------------------ 5 install / lint / test / build ---
#
# Read these out of the repository rather than inventing them. CI is the most
# reliable source: whatever the workflow runs is the real command.

INSTALL=null; LINT=null; TEST=null; TEST_SCOPED=null; BUILD=null

# PHPUnit — check composer.json for a non-default vendor-dir before assuming vendor/.
if [ -f phpunit.xml ] || [ -f phpunit.xml.dist ]; then
  VENDOR="$(grep -os '"vendor-dir"[[:space:]]*:[[:space:]]*"[^"]*"' composer.json 2>/dev/null | head -1 | sed 's/.*"vendor-dir"[[:space:]]*:[[:space:]]*"//; s/"$//')"
  [ -z "$VENDOR" ] && VENDOR="vendor"
  if [ -f "$VENDOR/bin/phpunit" ] || [ ! -d "$VENDOR" ]; then
    TEST="$(wrap "$VENDOR/bin/phpunit")"
    TEST_SCOPED="$(wrap "$VENDOR/bin/phpunit --filter {name}")"
  fi
fi

# pytest
if [ -f pytest.ini ] || [ -f tests/conftest.py ] || [ -f conftest.py ] || grep -qs '\[tool.pytest' pyproject.toml 2>/dev/null; then
  TEST="$(wrap "pytest")"
  TEST_SCOPED="$(wrap "pytest -k {name}")"
fi

# package.json scripts
if [ -f package.json ]; then
  grep -qs '"test"[[:space:]]*:' package.json && [ "$TEST" = "null" ] && TEST="$(wrap "npm test")"
  grep -qs '"build"[[:space:]]*:' package.json && BUILD="$(wrap "npm run build")"
  grep -qs '"lint"[[:space:]]*:' package.json && LINT="$(wrap "npm run lint")"
fi

# Install
if [ -f composer.json ]; then
  if [ "$EXEC_KIND" = "compose" ]; then
    INSTALL="docker compose run --rm ${EXEC_PREFIX##* } composer install"
  else
    INSTALL="$(wrap "composer install")"
  fi
elif [ -f requirements.txt ]; then
  INSTALL="$(wrap "pip install -r requirements.txt")"
elif [ -f pyproject.toml ]; then
  INSTALL="$(wrap "pip install -e .")"
elif [ -f package.json ]; then
  INSTALL="$(wrap "npm ci")"
fi

# Lint. {file} is substituted by the caller.
case "$FAMILY" in
  moodle-plugin|cms|php-app|php-library) [ "$LINT" = "null" ] && LINT="$(wrap "php -l {file}")" ;;
  python-app) have ruff && LINT="$(wrap "ruff check {file}")" ;;
esac

# CI overrides everything above — it is what actually gates the project.
CI_TEST=""
for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$wf" ] || continue
  CI_TEST="$(grep -hoE '(vendor/bin/phpunit|phpunit|pytest|npm (run )?test|go test)[^"'"'"']*' "$wf" 2>/dev/null | head -1)"
  [ -n "$CI_TEST" ] && break
done

# --------------------------------------------------------------- 6 runtime ---

RUNTIME_KIND=library
RUNTIME_HOW=null
case "$FAMILY" in
  moodle-plugin)
    RUNTIME_KIND=hosted
    RUNTIME_HOW="needs a Moodle installation; cannot run standalone"
    ;;
  php-app)
    if [ -f run ]; then RUNTIME_KIND=cli; RUNTIME_HOW="$(wrap "./run <command>")"; fi
    ;;
  python-app)
    if [ -f main.py ]; then RUNTIME_KIND=cli; RUNTIME_HOW="$(wrap "python main.py")"; fi
    ;;
esac

# A published port means the runtime is reachable from the HOST, not through exec.
if [ -n "$COMPOSE_FILE" ]; then
  PORT="$(grep -oE '^\s+-\s+"?[0-9]+:[0-9]+' "$COMPOSE_FILE" 2>/dev/null | head -1 | grep -oE '[0-9]+:' | head -1 | tr -d ':')"
  if [ -n "$PORT" ]; then
    RUNTIME_KIND=http
    RUNTIME_HOW="http://localhost:$PORT (from the host, not through exec)"
  fi
fi

# ------------------------------------------------------------ 7 timeoutTool ---
#
# Verify by behaviour, never by presence. macOS has no `timeout` at all unless
# coreutils is installed, where it is `gtimeout`. A presence check that guesses
# wrong produces checks that run nothing and report success, so run the thing.

TIMEOUT=null
if timeout 1 true >/dev/null 2>&1; then
  TIMEOUT=timeout
elif gtimeout 1 true >/dev/null 2>&1; then
  TIMEOUT=gtimeout
fi

# ----------------------------------------------------------- 8 hasDatabase ---
#
# Gates the data-safety rules, so a wrong `false` silently disables them. When
# unsure the answer is true: the cost is a few extra questions about dry-runs.

HASDB=false
if have rg; then
  rg -q --no-messages -e '\$DB->' -e 'get_records?\(' -e 'PDO' -e 'sqlalchemy' -e 'knex' \
       -e 'SELECT .* FROM' -g '!vendor' -g '!node_modules' . 2>/dev/null && HASDB=true
else
  grep -rqsE '\$DB->|get_records?\(|PDO|sqlalchemy|knex|SELECT .* FROM' \
       --exclude-dir=vendor --exclude-dir=node_modules --exclude-dir=.git . 2>/dev/null && HASDB=true
fi
if [ "$HASDB" = "false" ]; then
  for m in schema.sql db/install.xml db/upgrade.php migrations alembic db/tables; do
    [ -e "$m" ] && { HASDB=true; break; }
  done
fi

# ----------------------------------------------------------------- notes -----

NOTES=""
[ -n "$CI_TEST" ] && NOTES="CI runs: $CI_TEST"
[ "$TEST" = "null" ] && NOTES="${NOTES:+$NOTES; }No test command found — this repository may have no test suite."
[ -z "$NOTES" ] && NOTES=null

# ------------------------------------------------------------------ emit -----

mkdir -p .devskills
{
  printf '{\n'
  kv platform     "$PLATFORM";     printf ',\n'
  kv family       "$FAMILY";       printf ',\n'
  kv language     "$LANGUAGE";     printf ',\n'
  kv baseBranch   "$BASE";         printf ',\n'
  kv standardsDoc "$STANDARDS";    printf ',\n'
  printf '  "exec": {\n'
  printf '  '; kv kind "$EXEC_KIND"; printf ',\n'
  printf '  '; kv prefix "${EXEC_PREFIX:-null}"; printf ',\n'
  printf '  '; kv note "$EXEC_NOTE"; printf '\n'
  printf '  },\n'
  kv install    "$INSTALL";     printf ',\n'
  kv lint       "$LINT";        printf ',\n'
  kv test       "$TEST";        printf ',\n'
  kv testScoped "$TEST_SCOPED"; printf ',\n'
  kv build      "$BUILD";       printf ',\n'
  printf '  "runtime": {\n'
  printf '  '; kv kind "$RUNTIME_KIND"; printf ',\n'
  printf '  '; kv how "$RUNTIME_HOW"; printf '\n'
  printf '  },\n'
  kv hasDatabase "$HASDB";  printf ',\n'
  kv timeoutTool "$TIMEOUT"; printf ',\n'
  kv notes       "$NOTES";   printf '\n'
  printf '}\n'
} > "$CACHE"

cat "$CACHE"
