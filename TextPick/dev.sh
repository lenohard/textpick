#!/bin/bash
# Auto-rebuild and restart TextPick on source changes
# Usage: ./dev.sh

SCRIPT_DIR="$(dirname "$0")"
cd "$SCRIPT_DIR"

# Load .env
if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
fi

PID=""

kill_app() {
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "→ Killing old process ($PID)..."
        kill "$PID" 2>/dev/null
        wait "$PID" 2>/dev/null
    fi
}

build_and_run() {
    kill_app
    echo ""
    echo "⟳  Building..."
    if swift build 2>&1; then
        echo "✓  Build OK — launching..."
        swift run &
        PID=$!
    else
        echo "✗  Build failed, waiting for next change..."
    fi
}

trap 'kill_app; exit 0' INT TERM

# Initial build
build_and_run

# Watch Sources for .swift changes
echo ""
echo "👁  Watching Sources/ for changes. Ctrl-C to quit."
fswatch -o Sources | while read -r _; do
    echo "📝  Change detected"
    build_and_run
done
