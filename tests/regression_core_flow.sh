#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0
SKIPPED=0
PORT="${1:-19812}"
BASE="http://127.0.0.1:${PORT}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

log_pass() {
  echo -e "${GREEN}PASS${NC}: $1"
  PASSED=$((PASSED + 1))
}

log_fail() {
  echo -e "${RED}FAIL${NC}: $1"
  FAILED=$((FAILED + 1))
}

log_skip() {
  echo -e "${YELLOW}SKIP${NC}: $1"
  SKIPPED=$((SKIPPED + 1))
}

assert_status() {
  local label="$1"
  local expected="$2"
  local method="$3"
  local url="$4"
  local body="${5:-}"

  local actual
  if [ -n "$body" ]; then
    actual=$(curl -s -o /dev/null -w "%{http_code}" -X "$method" -H "Content-Type: application/json" -d "$body" "$url")
  else
    actual=$(curl -s -o /dev/null -w "%{http_code}" -X "$method" "$url")
  fi

  if [ "$actual" = "$expected" ]; then
    log_pass "$label (HTTP $actual)"
  else
    log_fail "$label (expected $expected, got $actual)"
  fi
}

assert_json_expr_equals() {
  local label="$1"
  local url="$2"
  local expr="$3"
  local expected="$4"

  local actual
  actual=$(curl -s "$url" | python3 -c "import json,sys; data=json.load(sys.stdin); print($expr)" 2>/dev/null || true)

  if [ "$actual" = "$expected" ]; then
    log_pass "$label"
  else
    log_fail "$label (expected '$expected', got '${actual:-<empty>}')"
  fi
}

find_first_instance() {
  curl -s "$BASE/api/status" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    print(":")
    raise SystemExit(0)
instances = data.get("instances", {}) if isinstance(data, dict) else {}
for component, names in instances.items():
    if isinstance(names, dict) and names:
        name = next(iter(names.keys()))
        print(f"{component}:{name}")
        raise SystemExit(0)
print(":")
'
}

echo "[regression] building nullhubx"
cd "$ROOT_DIR"
zig build
EXPECTED_VERSION=$(./zig-out/bin/nullhubx --version 2>&1 | awk '{print $2}' | sed 's/^v//')

echo "[regression] starting server on :$PORT"
./zig-out/bin/nullhubx serve --port "$PORT" >/tmp/nullhubx-regression.log 2>&1 &
SERVER_PID=$!

cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "[regression] waiting for health endpoint"
for i in $(seq 1 40); do
  if curl -s -o /dev/null -w "%{http_code}" "$BASE/health" | grep -q "200"; then
    break
  fi
  if [ "$i" -eq 40 ]; then
    echo "Server failed to start. Log: /tmp/nullhubx-regression.log"
    exit 1
  fi
  sleep 0.25
done

echo "[regression] API smoke"
assert_status "GET /health" "200" GET "$BASE/health"
assert_json_expr_equals "health.status == ok" "$BASE/health" "data.get('status')" "ok"

assert_status "GET /api/status" "200" GET "$BASE/api/status"
assert_json_expr_equals "status.hub.version matches binary" "$BASE/api/status" "(data.get('hub') or {}).get('version')" "$EXPECTED_VERSION"

assert_status "GET /api/components" "200" GET "$BASE/api/components"
assert_status "POST /api/components/refresh" "200" POST "$BASE/api/components/refresh"
assert_status "GET /api/instances" "200" GET "$BASE/api/instances"
assert_status "GET /api/settings" "200" GET "$BASE/api/settings"
assert_status "GET /api/updates" "200" GET "$BASE/api/updates"
assert_status "GET /api/service/status" "200" GET "$BASE/api/service/status"
assert_status "GET /api/nonexistent" "404" GET "$BASE/api/nonexistent"

INSTANCE_PAIR=$(find_first_instance)
INSTANCE_COMPONENT="${INSTANCE_PAIR%%:*}"
INSTANCE_NAME="${INSTANCE_PAIR##*:}"

if [ -z "$INSTANCE_COMPONENT" ] || [ "$INSTANCE_COMPONENT" = "$INSTANCE_NAME" ]; then
  log_skip "No instance found; skipping config/logs/agents checks"
else
  echo "[regression] instance checks on ${INSTANCE_COMPONENT}/${INSTANCE_NAME}"
  assert_status "GET instance config" "200" GET "$BASE/api/instances/${INSTANCE_COMPONENT}/${INSTANCE_NAME}/config"
  assert_status "GET instance logs SSE" "200" GET "$BASE/api/instances/${INSTANCE_COMPONENT}/${INSTANCE_NAME}/logs"

  if python3 "$ROOT_DIR/tests/smoke_agents_api.py" "$BASE" >/tmp/nullhubx-agents-smoke.log 2>&1; then
    log_pass "agents profiles/bindings smoke"
  else
    log_fail "agents profiles/bindings smoke (see /tmp/nullhubx-agents-smoke.log)"
  fi
fi

echo ""
echo "================================"
echo -e "Results: ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC}, ${YELLOW}${SKIPPED} skipped${NC}"
echo "================================"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
