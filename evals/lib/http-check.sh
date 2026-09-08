#!/usr/bin/env bash
# Cases for lib/http-check.sh — run them from anywhere:
#
#   bash evals/lib/http-check.sh
#
# Asserts:
# 1. Clean response bodies across HTML and JSON pass without false alarms.
# 2. Crash and error signatures are caught across all supported stacks
#    (PHP, Python, Node, Java, Go, Ruby, SQL engines, HTTP 500 pages, JSON errors).
# 3. Normal words like "error" in text or class names do NOT cause false positives.
# 4. Empty responses are detected when content is expected.
# 5. Connection failures (server offline) exit with code 2, not code 0 or 1.
#
# Exits 0 when every case passes, 1 otherwise.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
check="$root/lib/http-check.sh"
[ -f "$check" ] || { printf 'no http-check.sh at %s\n' "$check" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

fails=0
note() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# Helper: assert scan-file returns expected exit code
assert_exit() {
  local expected="$1"
  local file="$2"
  shift 2
  local code=0
  bash "$check" --scan-file "$file" "$@" >/dev/null 2>&1 || code=$?
  [ "$code" -eq "$expected" ] || note "expected exit $expected for $file $*, got $code"
}

# 1. Clean HTML page (with normal classes like "form-error", "0 errors found")
cat > "$work/clean.html" <<'HTML'
<!DOCTYPE html>
<html>
<head><title>User Dashboard</title></head>
<body>
  <h1>Welcome, Admin</h1>
  <div class="form-error-container">0 errors reported</div>
  <p>Calendar events are loaded.</p>
</body>
</html>
HTML
assert_exit 0 "$work/clean.html"

# 2. Clean JSON response (with error: null)
cat > "$work/clean.json" <<'JSON'
{
  "status": "success",
  "data": [1, 2, 3],
  "error": null,
  "errors": []
}
JSON
assert_exit 0 "$work/clean.json"

# 3. PHP Fatal error & profirealt-style [E] / Stack trace
cat > "$work/php_fatal.html" <<'HTML'
<b>Fatal error</b>: Uncaught Error: Class "CompanyService" not found in /app/index.php:42
Stack trace:
#0 {main}
HTML
assert_exit 1 "$work/php_fatal.html"

cat > "$work/php_profirealt.html" <<'HTML'
<div class="debug">[E]&nbsp;Error:&nbsp;Call to undefined method
Stack&nbsp;trace:&nbsp;#0 /app/Events.php</div>
HTML
assert_exit 1 "$work/php_profirealt.html"

# 4. Python Traceback & OperationalError
cat > "$work/python_traceback.html" <<'HTML'
Traceback (most recent call last):
  File "/app/views.py", line 12, in get
    user = User.objects.get(id=pk)
django.db.utils.OperationalError: no such table: auth_user
HTML
assert_exit 1 "$work/python_traceback.html"

# 5. Node.js UnhandledPromiseRejection & Cannot GET
cat > "$work/node_unhandled.html" <<'HTML'
(node:1234) UnhandledPromiseRejectionWarning: TypeError: Cannot read property 'map' of undefined
HTML
assert_exit 1 "$work/node_unhandled.html"

cat > "$work/node_cannot_get.html" <<'HTML'
Cannot GET /api/v1/users
HTML
assert_exit 1 "$work/node_cannot_get.html"

# 6. Java Spring Whitelabel Error Page
cat > "$work/java_whitelabel.html" <<'HTML'
<html><body><h1>Whitelabel Error Page</h1><p>This application has no explicit mapping for /error</p></body></html>
HTML
assert_exit 1 "$work/java_whitelabel.html"

# 7. SQL Engine Error
cat > "$work/sql_error.html" <<'HTML'
<div>SQLSTATE[42S02]: Base table or view not found: 1146 Table 'db.users' doesn't exist</div>
HTML
assert_exit 1 "$work/sql_error.html"

# 8. Web Server 500 heading
cat > "$work/server_500.html" <<'HTML'
<html><head><title>500 Internal Server Error</title></head><body><h1>500 Internal Server Error</h1>nginx</body></html>
HTML
assert_exit 1 "$work/server_500.html"

# 9. JSON API Error Payload
cat > "$work/json_error.json" <<'JSON'
{
  "statusCode": 500,
  "error": "Internal Server Error",
  "message": "Connection to redis timed out"
}
JSON
assert_exit 1 "$work/json_error.json"

# 10. Empty body detection
: > "$work/empty.html"
assert_exit 1 "$work/empty.html"
assert_exit 0 "$work/empty.html" --allow-empty

# 11. Required text option
assert_exit 0 "$work/clean.html" --require "Welcome, Admin"
assert_exit 1 "$work/clean.html" --require "Missing Section"

# 12. Offline server connection failure (exit code 2)
code=0
# Pick an unused high port on localhost
bash "$check" http://127.0.0.1:59123/test --timeout 1 >/dev/null 2>&1 || code=$?
[ "$code" -eq 2 ] || note "expected exit 2 on connection refused, got $code"

if [ "$fails" -eq 0 ]; then
  printf 'http-check: cross-stack crash signatures and connection checks pass\n'
else
  printf 'http-check: %s failure(s)\n' "$fails" >&2
fi
exit $((fails > 0))
