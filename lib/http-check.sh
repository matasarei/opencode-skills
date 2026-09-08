#!/usr/bin/env bash
# Verify an HTTP route or response body across tech stacks.
#
# Checks:
# 1. Connection / network exit code (detects connection refused, timeouts)
# 2. HTTP status code (default 200, or --expect-status <code|regex>)
# 3. Auth drop detection (redirect to /login, or password fields rendered on protected routes)
# 4. Empty body detection (0 bytes is a failure unless --allow-empty)
# 5. Cross-stack crash signatures (PHP, Python, Node, Java, Go, Ruby, SQL)
# 6. Web server gateway errors (Nginx/Apache 500/502/503/504 default pages)
# 7. JSON API error payloads & failures (error, statusCode: 5xx, success: false, status: error)
# 8. Required / rejected content assertions (--require <text>, --reject <pattern>)
#
# Usage:
#   http-check.sh <url> [options] [-- curl-options]
#   http-check.sh --scan-file <path> [options]
#
# Options:
#   --expect-status <code|regex>  Expected status code (default: '200')
#   --require <text>              Text that must be present in body
#   --reject <pattern>            Regex pattern that must NOT be present in body
#   --allow-empty                 Allow 0-byte response bodies
#   --allow-login                 Allow login forms / auth redirects (when testing login itself)
#   --scan-file <path>            Scan an existing file instead of making a network call
#   --timeout <seconds>           curl connection timeout (default: 10)
#
# Exit codes:
#   0  Clean: correct status, non-empty, expected content present, no errors/auth drops
#   1  Failed check: wrong status, auth drop, empty body, error signature, or requirement failed
#   2  Connection / network failure: connection refused, DNS error, timeout

set -u

URL=""
SCAN_FILE=""
EXPECT_STATUS="200"
REQUIRE_TEXT=""
REJECT_PATTERN=""
ALLOW_EMPTY=0
ALLOW_LOGIN=0
TIMEOUT=10
CURL_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --scan-file)
      SCAN_FILE="${2:-}"
      shift 2 || true
      ;;
    --expect-status)
      EXPECT_STATUS="${2:-}"
      shift 2 || true
      ;;
    --require)
      REQUIRE_TEXT="${2:-}"
      shift 2 || true
      ;;
    --reject)
      REJECT_PATTERN="${2:-}"
      shift 2 || true
      ;;
    --allow-empty)
      ALLOW_EMPTY=1
      shift
      ;;
    --allow-login)
      ALLOW_LOGIN=1
      shift
      ;;
    --timeout)
      TIMEOUT="${2:-10}"
      shift 2 || true
      ;;
    --)
      shift
      CURL_ARGS+=("$@")
      break
      ;;
    http://*|https://*)
      URL="$1"
      shift
      ;;
    -*)
      CURL_ARGS+=("$1")
      shift
      ;;
    *)
      if [ -z "$URL" ] && [ -z "$SCAN_FILE" ]; then
        if [ -f "$1" ]; then
          SCAN_FILE="$1"
        else
          URL="$1"
        fi
      else
        CURL_ARGS+=("$1")
      fi
      shift
      ;;
  esac
done

IS_LOGIN_TARGET=0
case "$URL" in
  */login|*/login/*|*/login\?*|*/login.*|*/signin|*/signin/*|*/signin\?*|*/sign-in*|*/sessions/new*|*/auth|*/auth/*) IS_LOGIN_TARGET=1 ;;
esac
if [ -n "$SCAN_FILE" ]; then
  case "$(basename "$SCAN_FILE")" in
    login*|signin*|sign-in*) IS_LOGIN_TARGET=1 ;;
  esac
fi

# Error signatures pattern list (regexes tested per line or across file)
# Grouped by stack to give clear failure reasons.
scan_body_errors() {
  local file="$1"

  # 0. Auth drop: Login form or password field returned on a non-login route
  if [ "$ALLOW_LOGIN" -eq 0 ] && [ "$IS_LOGIN_TARGET" -eq 0 ]; then
    local auth_match
    auth_match="$(grep -niE '<input[^>]*type=["'"'"']?password["'"'"']?|<form[^>]*action=["'"'"'][^"'"'"']*(login|signin)' "$file" | head -1 || true)"
    if [ -n "$auth_match" ]; then
      printf 'Auth failure (received login form or password field on protected route): %s\n' "$auth_match"
      return 1
    fi
  fi

  # 1. PHP Fatal / Exceptions / Warnings / Debug markers
  local php_match
  php_match="$(grep -nE "(Fatal error|Parse error)(</b>)?:|Uncaught (Exception|Error|TypeError|[A-Za-z0-9_]+Exception):|Stack(&nbsp;| )trace:|\[E\](&nbsp;| )(Error|Warning|Notice):" "$file" | head -1 || true)"
  if [ -n "$php_match" ]; then
    printf 'PHP crash/error signature found: %s\n' "$php_match"
    return 1
  fi

  # 2. Python tracebacks & exceptions
  local py_match
  py_match="$(grep -nE "Traceback \(most recent call last\):|(django\.db\.utils|sqlalchemy\.exc\.)|(OperationalError|IntegrityError|ZeroDivisionError|AttributeError|NameError):" "$file" | head -1 || true)"
  if [ -n "$py_match" ]; then
    printf 'Python crash/traceback found: %s\n' "$py_match"
    return 1
  fi

  # 3. Node.js / JavaScript runtime errors
  local node_match
  node_match="$(grep -nE "UnhandledPromiseRejection|UnhandledPromiseRejectionWarning|Error \[ERR_|Cannot (GET|POST|PUT|DELETE) /" "$file" | head -1 || true)"
  if [ -n "$node_match" ]; then
    printf 'Node.js error signature found: %s\n' "$node_match"
    return 1
  fi

  # 4. Java / JVM / Spring errors
  local java_match
  java_match="$(grep -nE "Whitelabel Error Page|Exception in thread \"|java\.lang\.NullPointerException|org\.springframework\.[A-Za-z0-9_]+Exception" "$file" | head -1 || true)"
  if [ -n "$java_match" ]; then
    printf 'Java/Spring error signature found: %s\n' "$java_match"
    return 1
  fi

  # 5. Go / Rust panics
  local compiled_match
  compiled_match="$(grep -nE "panic: |goroutine [0-9]+ \[running\]:|thread '.*' panicked at" "$file" | head -1 || true)"
  if [ -n "$compiled_match" ]; then
    printf 'Go/Rust panic found: %s\n' "$compiled_match"
    return 1
  fi

  # 6. Ruby on Rails errors
  local ruby_match
  ruby_match="$(grep -nE "(ActionView::Template::Error|ActiveRecord::[A-Za-z0-9_]+Error|RoutingError \(No route matches)" "$file" | head -1 || true)"
  if [ -n "$ruby_match" ]; then
    printf 'Ruby/Rails error found: %s\n' "$ruby_match"
    return 1
  fi

  # 7. Database / SQL engine errors
  local db_match
  db_match="$(grep -nE "SQLSTATE\[[0-9A-Z]+\]|syntax error at or near \"|ORA-[0-9]{5}|sqlite3\.OperationalError:|QueryFailedError:" "$file" | head -1 || true)"
  if [ -n "$db_match" ]; then
    printf 'Database/SQL error found: %s\n' "$db_match"
    return 1
  fi

  # 8. Web server default error pages & English application error screens (even on soft-200)
  local srv_pattern='<title>[[:space:]]*(500 Internal Server Error|502 Bad Gateway|503 Service Unavailable|504 Gateway Time-out|Server Error|Internal Server Error|Application Error|Access Denied|403 Forbidden|404 Not Found)[[:space:]]*</title>|<h[12][^>]*>[[:space:]]*(500 Internal Server Error|Bad Gateway|Server Error|Internal Server Error|Application Error|Something went wrong|An error occurred|Access Denied|403 Forbidden|404 Not Found)[[:space:]]*</h[12]>|Whoops! There was an error|Server Error in .Application|Application error: a client-side exception has occurred|The server returned a .*500 Internal Server Error|Action Controller: Exception caught'
  local srv_match
  srv_match="$(grep -niE "$srv_pattern" "$file" | head -1 || true)"
  if [ -n "$srv_match" ]; then
    printf 'Server or application error page found: %s\n' "$srv_match"
    return 1
  fi

  # 9. JSON API explicit error payloads & failures (excluding null/false/empty)
  if grep -qsE '^[[:space:]]*\{' "$file"; then
    local json_err
    json_err="$(grep -nE '"(error|error_message)":[[:space:]]*"[^"]+"|"statusCode":[[:space:]]*5[0-9]{2}|"success":[[:space:]]*false|"authenticated":[[:space:]]*false|"status":[[:space:]]*"(error|fail)"' "$file" | head -1 || true)"
    if [ -n "$json_err" ]; then
      printf 'JSON API error payload found: %s\n' "$json_err"
      return 1
    fi
  fi

  # 10. Explicit reject pattern if specified
  if [ -n "$REJECT_PATTERN" ]; then
    local rej_match
    rej_match="$(grep -nE "$REJECT_PATTERN" "$file" | head -1 || true)"
    if [ -n "$rej_match" ]; then
      printf 'Rejected pattern found matching "%s": %s\n' "$REJECT_PATTERN" "$rej_match"
      return 1
    fi
  fi

  return 0
}

# Mode 1: Scan local file directly
if [ -n "$SCAN_FILE" ]; then
  [ -f "$SCAN_FILE" ] || { echo "FAIL: file not found: $SCAN_FILE" >&2; exit 1; }

  if [ "$ALLOW_EMPTY" -eq 0 ]; then
    if [ ! -s "$SCAN_FILE" ] || [ -z "$(tr -d '[:space:]' < "$SCAN_FILE")" ]; then
      echo "FAIL EMPTY: file is 0 bytes or whitespace-only: $SCAN_FILE" >&2
      exit 1
    fi
    if tr '\n' ' ' < "$SCAN_FILE" | grep -qiE '<body[^>]*>[[:space:]]*</body>'; then
      echo "FAIL EMPTY: file contains an empty <body> (White Screen of Death): $SCAN_FILE" >&2
      exit 1
    fi
  fi

  if [ -n "$REQUIRE_TEXT" ]; then
    if ! grep -qF -- "$REQUIRE_TEXT" "$SCAN_FILE"; then
      echo "FAIL MISSING: file does not contain required text: '$REQUIRE_TEXT'" >&2
      exit 1
    fi
  fi

  if err="$(scan_body_errors "$SCAN_FILE")"; then
    echo "OK: $SCAN_FILE ($(wc -c < "$SCAN_FILE" | tr -d ' ') bytes) clean"
    exit 0
  else
    echo "FAIL: $err" >&2
    exit 1
  fi
fi

[ -n "$URL" ] || { echo "Usage: http-check.sh <url> [options]" >&2; exit 1; }

TMP_BODY="$(mktemp "${TMPDIR:-/tmp}/http_body.XXXXXX")"
trap 'rm -f "$TMP_BODY"' EXIT

# Run curl: write body to $TMP_BODY, print status code and effective url to stdout
CURL_OUT="$(curl -s -S -L --max-time "$TIMEOUT" -w "\n%{http_code}\n%{url_effective}" -o "$TMP_BODY" "${CURL_ARGS[@]}" "$URL" 2>&1)"
CURL_EXIT=$?

if [ "$CURL_EXIT" -ne 0 ]; then
  echo "FAIL CONNECTION: curl exited with $CURL_EXIT - $CURL_OUT" >&2
  exit 2
fi

# Extract the HTTP status code and effective URL
STATUS_CODE="$(printf '%s\n' "$CURL_OUT" | tail -2 | head -1 | tr -d ' \r\n')"
EFFECTIVE_URL="$(printf '%s\n' "$CURL_OUT" | tail -1 | tr -d ' \r\n')"

# Auth drop via redirect:
if [ "$ALLOW_LOGIN" -eq 0 ] && [ "$IS_LOGIN_TARGET" -eq 0 ]; then
  case "$EFFECTIVE_URL" in
    */login*|*/signin*|*/sign-in*|*/auth/*|*/auth|*/sessions/new*)
      echo "FAIL AUTH REDIRECT: requested '$URL' but got redirected to login page: '$EFFECTIVE_URL'" >&2
      exit 1
      ;;
  esac
fi

# Validate HTTP status code against EXPECT_STATUS (regex match)
if ! [[ "$STATUS_CODE" =~ ^($EXPECT_STATUS)$ ]]; then
  echo "FAIL STATUS: expected status matching '$EXPECT_STATUS', got $STATUS_CODE for $URL" >&2
  if [ -s "$TMP_BODY" ]; then
    echo "Response preview (first 5 lines):" >&2
    head -5 "$TMP_BODY" >&2
  fi
  exit 1
fi

# Check empty body (0 bytes, whitespace-only, or empty <body> White Screen of Death)
if [ "$ALLOW_EMPTY" -eq 0 ] && [ "$STATUS_CODE" != "204" ] && [ "$STATUS_CODE" != "304" ]; then
  if [ ! -s "$TMP_BODY" ] || [ -z "$(tr -d '[:space:]' < "$TMP_BODY")" ]; then
    echo "FAIL EMPTY: response body is 0 bytes or whitespace-only (HTTP $STATUS_CODE) for $URL" >&2
    exit 1
  fi
  if tr '\n' ' ' < "$TMP_BODY" | grep -qiE '<body[^>]*>[[:space:]]*</body>'; then
    echo "FAIL EMPTY: response contains an empty <body> tag (White Screen of Death) for $URL" >&2
    exit 1
  fi
fi

# Check required text
if [ -n "$REQUIRE_TEXT" ]; then
  if ! grep -qF -- "$REQUIRE_TEXT" "$TMP_BODY"; then
    echo "FAIL MISSING: response body does not contain required '$REQUIRE_TEXT' for $URL" >&2
    exit 1
  fi
fi

# Scan for error signatures and auth drops
if err="$(scan_body_errors "$TMP_BODY")"; then
  BYTES="$(wc -c < "$TMP_BODY" | tr -d ' ')"
  echo "OK HTTP $STATUS_CODE ($BYTES bytes) - $URL"
  exit 0
else
  echo "FAIL: $err" >&2
  echo "URL: $URL (HTTP $STATUS_CODE)" >&2
  exit 1
fi
