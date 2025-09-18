#!/bin/bash

# Default values for PORT and HOST
PORT="${1:-9300}"
HOST="${2:-localhost}"

# Always resolve repo root (assume scripts/ is sibling of mcp-playwright/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$SCRIPT_DIR/mcp-playwright"
EXECUTABLE="$REPO_DIR/dist/index.js"

if [ ! -f "$EXECUTABLE" ]; then
    echo "Error: Cannot find playwright-mcp-server executable at $EXECUTABLE."
    exit 1
fi

# Start the server
echo "Starting Playwright MCP Server on port $PORT and host $HOST ..."
node "$EXECUTABLE" --port "$PORT" --host "$HOST"
