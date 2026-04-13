#!/bin/bash
set -e

# Load .env if present
if [ -f "$(dirname "$0")/.env" ]; then
    export $(grep -v '^#' "$(dirname "$0")/.env" | xargs)
fi

cd "$(dirname "$0")"
swift run
