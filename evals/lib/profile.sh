#!/usr/bin/env bash
# Cases for lib/profile.sh — run them from anywhere:
#
#   bash evals/lib/profile.sh
#
# The profile is the fact every skill starts from, so what is asserted is that
# each field follows its fixture: family, language, test and lint commands,
# hasDatabase, the CI note, the base branch — and that null is a real answer
# for a repository with none of them. Docker is stubbed out so the result is
# the host fallback on every machine; the mount probe has its own note in the
# README and is not exercised here.
#
# Exits 0 when every case matches, 1 otherwise, naming each mismatch.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
profile="$root/lib/profile.sh"
[ -f "$profile" ] || { printf 'no profile.sh at %s\n' "$profile" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
g() { git -C "$1" -c user.email=t@e -c user.name=t "${@:2}"; }
field() { printf '%s\n' "$out" | sed -n "s/^ *\"$1\": *\(.*\)$/\1/p" | sed -n "${2:-1}p" | sed 's/,$//'; }
want() { [ "$(field "$1")" = "$2" ] || note "$3: $1 = $(field "$1"), want $2"; }
# "kind" appears twice — exec.kind first, runtime.kind second.
want_runtime() { [ "$(field kind 2)" = "$1" ] || note "$2: runtime.kind = $(field kind 2), want $1"; }

# A docker that is installed but whose daemon never answers: the host fallback,
# deterministically, whatever this machine has.
stub="$work/bin"; mkdir -p "$stub"
printf '#!/bin/sh\nexit 1\n' > "$stub/docker"; chmod +x "$stub/docker"
run() { out="$(cd "$1" && PATH="$stub:$PATH" bash "$profile" "${2:-}" 2>&1)"; }

# A PHP library with PHPUnit, a database call, a CI workflow, no compose file.
lib="$work/lib"; mkdir -p "$lib/src" "$lib/tests" "$lib/.github/workflows"
printf '{"name":"x/y","type":"library","require":{"php":">=7.4"}}\n' > "$lib/composer.json"
printf '<phpunit/>\n' > "$lib/phpunit.xml"
printf '<?php $DB->get_record("user", []);\n' > "$lib/src/Repo.php"
printf 'jobs:\n  t:\n    steps:\n      - run: vendor/bin/phpunit --testsuite unit\n' > "$lib/.github/workflows/ci.yml"
printf '# Conventions\n' > "$lib/CONTRIBUTING.md"
g "$lib" init -q -b main . && g "$lib" add -A && g "$lib" commit -qm init

run "$lib"
want family '"php-library"' 'php library'
want language '"PHP >=7.4"' 'php library'
want baseBranch '"main"' 'php library'
want standardsDoc '"CONTRIBUTING.md"' 'php library'
want kind '"host"' 'php library'
want_runtime '"library"' 'php library'
want test '"vendor/bin/phpunit"' 'php library'
want testScoped '"vendor/bin/phpunit --filter {name}"' 'php library'
want lint '"php -l {file}"' 'php library'
want install '"composer install"' 'php library'
want hasDatabase 'true' 'php library'
printf '%s\n' "$out" | grep -q 'CI runs: vendor/bin/phpunit --testsuite unit' || note 'php library: the CI run line is not in notes'
printf '%s\n' "$out" | grep -q '"note": "Docker not available' || note 'php library: the host fallback reason is not recorded'
[ -f "$lib/.devskills/profile.json" ] || note 'php library: the cache was not written'

# The cache is what is printed the second time, even after the tree changes.
rm "$lib/phpunit.xml"
run "$lib"
want test '"vendor/bin/phpunit"' 'cached'
# --reprofile detects again and sees the change.
run "$lib" --reprofile
want test 'null' 'reprofiled'
printf '%s\n' "$out" | grep -q 'No test command found' || note 'reprofiled: the missing test command is not noted'
# --path prints the cache path and nothing else.
run "$lib" --path
[ "$out" = '.devskills/profile.json' ] || note "--path: got '$out'"

# A repository with none of it: nulls, not inventions.
bare="$work/bare"; mkdir -p "$bare"
g "$bare" init -q -b master . && g "$bare" commit -q --allow-empty -m init   # an unborn branch is no branch
run "$bare"
want family '"other"' 'bare'
want language 'null' 'bare'
want baseBranch '"master"' 'bare'
want standardsDoc 'null' 'bare'
want test 'null' 'bare'
want lint 'null' 'bare'
want install 'null' 'bare'
want hasDatabase 'false' 'bare'
want_runtime '"library"' 'bare'
case "$(field timeoutTool)" in '"timeout"'|'"gtimeout"'|null) ;; *) note "bare: timeoutTool = $(field timeoutTool)" ;; esac

# A python app with pytest: the other detection branch.
py="$work/py"; mkdir -p "$py/tests"
printf '[project]\nrequires-python = ">=3.11"\n[tool.pytest.ini_options]\n' > "$py/pyproject.toml"
printf '\n' > "$py/tests/conftest.py"
printf 'print(1)\n' > "$py/main.py"
g "$py" init -q -b main .
run "$py"
want family '"python-app"' 'python'
want language '"Python >=3.11"' 'python'
want test '"pytest"' 'python'
want install '"pip install -e ."' 'python'
want_runtime '"cli"' 'python'
want how '"python main.py"' 'python'
want contextTokens '100000' 'python'

# contextTokens: the default, and the DEV_SKILLS_CONTEXT override (a number, unquoted).
out="$(cd "$py" && PATH="$stub:$PATH" DEV_SKILLS_CONTEXT=64000 bash "$profile" --reprofile 2>&1)"
want contextTokens '64000' 'override'
out="$(cd "$py" && PATH="$stub:$PATH" DEV_SKILLS_CONTEXT=lots bash "$profile" --reprofile 2>&1)"
want contextTokens '100000' 'non-numeric override falls back'

# A PHP app with docker compose having mysql, fpm, nginx:
# verifies that fpm is selected, and mysql is never chosen.
compose_app="$work/compose_app"; mkdir -p "$compose_app"
printf '{"require":{"php":">=8.0"}}\n' > "$compose_app/composer.json"
printf 'services:\n  mysql:\n  fpm:\n  nginx:\n' > "$compose_app/docker-compose.yml"
g "$compose_app" init -q -b main . && g "$compose_app" add -A && g "$compose_app" commit -qm init

compose_stub="$work/compose_bin"; mkdir -p "$compose_stub"
cat > "$compose_stub/docker" <<'DOCKER'
#!/bin/sh
case "$*" in
  "info") exit 0 ;;
  *"config --services"*) printf 'mysql\nfpm\nnginx\n'; exit 0 ;;
  *"ps --status running"*) printf 'mysql\nfpm\nnginx\n'; exit 0 ;;
  *"exec -T fpm which php"*) exit 0 ;;
  *"exec -T mysql which php"*) exit 1 ;;
  *) exit 0 ;;
esac
DOCKER
chmod +x "$compose_stub/docker"
out="$(cd "$compose_app" && PATH="$compose_stub:$PATH" bash "$profile" 2>&1)"
want kind '"compose"' 'compose app'
want prefix '"docker compose exec -T fpm"' 'compose selects fpm over mysql'

if [ "$fails" -eq 0 ]; then
  printf 'profile: every field follows its fixture, null included\n'
else
  printf 'profile: %s case(s) failed\n' "$fails" >&2
fi
exit $((fails > 0))
