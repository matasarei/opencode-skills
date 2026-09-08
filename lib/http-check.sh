#!/usr/bin/env bash
# Verify an HTTP route or response body across tech stacks.
#
# Checks:
# 1. Connection / network exit code (detects connection refused, timeouts)
# 2. HTTP status code (default 200, or --expect-status <code|regex>)
# 3. Empty body detection (0 bytes is a failure unless --allow-empty)
# 4. Cross-stack body error signatures (PHP, Python, Node, Java, Go, Ruby, SQL)
#
# Usage:
#   http-check.sh <url> [options] [-- curl-options]
#   http-check.sh --scan-file <path> [options]
#
# Options:
#   --expect-status <code|regex>  Expected status code (default: '200')
#   --require <text>              Text that must be present in body
#   --allow-empty                 Allow 0-byte response bodies
#   --scan-file <path>            Scan an existing file instead of making a network call
#   --timeout <seconds>           curl connection timeout (default: 10)
#
# Exit codes:
#   0  Clean: correct status, non-empty, no error signatures found
#   1  Failed check: wrong status, empty body, missing required text, or error signature
#   2  Connection / network failure: connection refused, DNS error, timeout

set -u

URL=""
SCAN_FILE=""
EXPECT_STATUS="200"
REQUIRE_TEXT=""
ALLOW_EMPTY=0
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
    --allow-empty)
      ALLOW_EMPTY=1
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

# Error signatures pattern list (regexes tested per line or across file)
# Grouped by stack to give clear failure reasons.
scan_body_errors() {
  local file="$1"

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

  # 8. Web server default error pages (500/502/503/504)
  local srv_match
  srv_match="$(grep -nE "<title>(500 Internal Server Error|502 Bad Gateway|503 Service Unavailable|504 Gateway Time-out)</title>|<h1>(500 Internal Server Error|Bad Gateway|Server Error \(500\))</h1>" "$file" | head -1 || true)"
  if [ -n "$srv_match" ]; then
    printf 'Server error page found: %s\n' "$srv_match"
    return 1
  fi

  # 9. JSON API explicit error payloads (excluding null/false/empty)
  # Look for "error": "...", "errors": [...], or "statusCode": 5xx
  if grep -qsE '^[[:space:]]*\{' "$file"; then
    local json_err
    json_err="$(grep -nE '"(error|error_message)":[[:space:]]*"[^"]+"|"statusCode":[[:space:]]*5[0-9]{2}' "$file" | head -1 || true)"
    if [ -n "$json_err" ]; then
      printf 'JSON API error payload found: %s\n' "$json_err"
      return 1
    fi
  fi

  return 0
}

# Mode 1: Scan local file directly
if [ -n "$SCAN_FILE" ]; then
  [ -f "$SCAN_FILE" ] || { echo "FAIL: file not found: $SCAN_FILE" >&2; exit 1; }
  
  if [ "$ALLOW_EMPTY" -eq 0 ] && [ ! -s "$SCAN_FILE" ]; then
    echo "FAIL EMPTY: file is 0 bytes: $SCAN_FILE" >&2
    exit 1
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

# Mode 2: Live HTTP Request via curl
[ -n "$URL" ] || { echo "Usage: http-check.sh <url> [options]" >&2; exit 1; }

TMP_BODY="$(mktemp "${TMPDIR:-/tmp}/http_body.XXXXXX")"
trap 'rm -f "$TMP_BODY"' EXIT

# Run curl: write body to $TMP_BODY, print status code to stdout
CURL_OUT="$(curl -s -S -L --max-time "$TIMEOUT" -w "\n%{http_code}" -o "$TMP_BODY" "${CURL_ARGS[@]}" "$URL" 2>&1)"
CURL_EXIT=$?

if [ "$CURL_EXIT" -ne 0 ]; then
  echo "FAIL CONNECTION: curl exited with code $CURL_EXIT ($CURL_OUT)" >&2
  exit 2
fi

# Extract the HTTP status code from the last line
STATUS_CODE="$(printf '%s\n' "$CURL_OUT" | tail -1 | tr -d ' \r\n')"

# Validate HTTP status code against EXPECT_STATUS (regex match)
if ! [[ "$STATUS_CODE" =~ ^($EXPECT_STATUS)$ ]]; then
  echo "FAIL STATUS: expected status matching '$EXPECT_STATUS', got $STATUS_CODE for $URL" >&2
  if [ -s "$TMP_BODY" ]; then
    echo "Response preview (first 5 lines):" >&2
    head -5 "$TMP_BODY" >&2
  fi
  exit 1
fi

# Check empty body
if [ "$ALLOW_EMPTY" -eq 0 ] && [ ! -s "$TMP_BODY" ] && [ "$STATUS_CODE" != "204" ] && [ "$STATUS_CODE" != "304" ]; then
  echo "FAIL EMPTY: response body is 0 bytes (HTTP $STATUS_CODE) for $URL" >&2
  exit 1
fi

# Check required text
if [ -n "$REQUIRE_TEXT" ]; then
  if ! grep -qF -- "$REQUIRE_TEXT" "$TMP_BODY"; then
    echo "FAIL MISSING: response body does not contain required '$REQUIRE_TEXT' for $URL" >&2
    exit 1
  fi
fi

# Scan for error signatures
if err="$(scan_body_errors "$TMP_BODY")"; then
  BYTES="$(wc -c < "$TMP_BODY" | tr -d ' ')"
  echo "OK HTTP $STATUS_CODE ($BYTES bytes) - $URL"
  exit 0
else
  echo "FAIL: $err" >&2
  echo "URL: $URL (HTTP $STATUS_CODE)" >&2
  exit 1
fi
