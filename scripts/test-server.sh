#!/bin/bash
PORT=${1:-9300}
BASE_URL="http://localhost:$PORT"
echo "Testing Playwright MCP Server at $BASE_URL"
curl -s -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' "$BASE_URL/mcp"
