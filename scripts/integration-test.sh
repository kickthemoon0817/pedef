#!/bin/bash
# integration-test.sh — Build and test both PedefSync server and Pedef app.
#
# Usage:
#   ./scripts/integration-test.sh           # run all stages
#   ./scripts/integration-test.sh --server  # server build + test only
#   ./scripts/integration-test.sh --app     # app build + test only
#   ./scripts/integration-test.sh --smoke   # server smoke test (start, port check, stop)
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_DIR="$PROJECT_DIR/PedefSync"
TEST_TOKEN="integration-test-token-$(date +%s)"
TEST_PORT=50099
TEST_DATA_DIR=""
SERVER_PID=""

# --- Helpers ----------------------------------------------------------------

info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }
fail()  { printf '\033[1;31m[FAIL]\033[0m  %s\n' "$*"; exit 1; }

cleanup() {
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        info "Stopping server (PID $SERVER_PID)"
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    if [ -n "$TEST_DATA_DIR" ] && [ -d "$TEST_DATA_DIR" ]; then
        info "Cleaning up temp data: $TEST_DATA_DIR"
        rm -rf "$TEST_DATA_DIR"
    fi
}
trap cleanup EXIT

wait_for_port() {
    local port=$1 max_wait=${2:-15} elapsed=0
    while ! lsof -iTCP:"$port" -sTCP:LISTEN -P -n >/dev/null 2>&1; do
        sleep 1
        elapsed=$((elapsed + 1))
        if [ "$elapsed" -ge "$max_wait" ]; then
            return 1
        fi
    done
    return 0
}

# --- Stages -----------------------------------------------------------------

build_server() {
    info "Building PedefSync server..."
    cd "$SERVER_DIR"
    swift build 2>&1
    ok "PedefSync server built successfully"
}

test_server() {
    info "Running PedefSync server tests..."
    cd "$SERVER_DIR"
    swift test 2>&1
    ok "PedefSync server tests passed"
}

smoke_test_server() {
    info "Starting smoke test — launching server on port $TEST_PORT..."
    TEST_DATA_DIR="$(mktemp -d)"

    cd "$SERVER_DIR"
    swift run PedefSync --hostname 127.0.0.1 --port "$TEST_PORT" \
        --token "$TEST_TOKEN" --data-dir "$TEST_DATA_DIR" &
    SERVER_PID=$!

    info "Waiting for server (PID $SERVER_PID) to listen on port $TEST_PORT..."
    if wait_for_port "$TEST_PORT" 30; then
        ok "Server is listening on port $TEST_PORT"
    else
        fail "Server failed to start within 30 seconds"
    fi

    # Verify process is still alive (didn't crash after binding)
    sleep 2
    if kill -0 "$SERVER_PID" 2>/dev/null; then
        ok "Server still running after 2 s"
    else
        fail "Server process exited unexpectedly"
    fi

    info "Stopping server..."
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
    ok "Smoke test passed"
}

build_app() {
    info "Building Pedef app..."
    cd "$PROJECT_DIR"
    xcodebuild -scheme Pedef -configuration Debug build \
        -destination 'platform=macOS' 2>&1 | tail -5
    ok "Pedef app built successfully"
}

test_app() {
    info "Running Pedef app tests..."
    cd "$PROJECT_DIR"
    xcodebuild -scheme Pedef test \
        -destination 'platform=macOS' 2>&1 | tail -20
    ok "Pedef app tests passed"
}

# --- Main -------------------------------------------------------------------

RUN_SERVER=false
RUN_APP=false
RUN_SMOKE=false

if [ $# -eq 0 ]; then
    RUN_SERVER=true; RUN_APP=true; RUN_SMOKE=true
else
    for arg in "$@"; do
        case "$arg" in
            --server) RUN_SERVER=true ;;
            --app)    RUN_APP=true ;;
            --smoke)  RUN_SMOKE=true ;;
            *)        fail "Unknown argument: $arg" ;;
        esac
    done
fi

info "=== Pedef Integration Test Suite ==="

if $RUN_SERVER; then
    build_server
    test_server
fi

if $RUN_SMOKE; then
    build_server  # ensure binary is up to date
    smoke_test_server
fi

if $RUN_APP; then
    build_app
    test_app
fi

info "=== All requested stages complete ==="
ok "Integration tests finished successfully"

