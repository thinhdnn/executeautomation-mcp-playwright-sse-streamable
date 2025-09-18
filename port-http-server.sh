#!/bin/bash
# port-http-server.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$SCRIPT_DIR/mcp-playwright"
PORT=${1:-9300}
HOST=${2:-localhost}

# Ensure src and scripts directories exist in repo
mkdir -p "$REPO_DIR/src" "$REPO_DIR/scripts"

# 1. src/transport.ts
cat > "$REPO_DIR/src/transport.ts" <<EOF
import http from 'http';
import assert from 'assert';
import crypto from 'crypto';
import { SSEServerTransport } from '@modelcontextprotocol/sdk/server/sse.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import type { AddressInfo } from 'net';

export async function startStdioTransport(server: Server) {
  await server.connect(new StdioServerTransport());
}

async function handleSSE(server, req, res, url, sessions) {
  const timestamp = new Date().toISOString();
  console.error(\`[\${timestamp}] SSE Request: \${req.method} \${req.url} from \${req.socket.remoteAddress}\`);
  if (req.method === 'POST') {
    const sessionId = url.searchParams.get('sessionId');
    if (!sessionId) {
      res.statusCode = 400;
      return res.end('Missing sessionId');
    }
    const transport = sessions.get(sessionId);
    if (!transport) {
      res.statusCode = 404;
      return res.end('Session not found');
    }
    return await transport.handlePostMessage(req, res);
  } else if (req.method === 'GET') {
    const transport = new SSEServerTransport('/sse', res);
    sessions.set(transport.sessionId, transport);
    await server.connect(transport);
    res.on('close', () => {
      sessions.delete(transport.sessionId);
    });
    return;
  }
  res.statusCode = 405;
  res.end('Method not allowed');
}

async function handleStreamable(server, req, res, sessions) {
  const timestamp = new Date().toISOString();
  const sessionId = req.headers['mcp-session-id'];
  if (sessionId) {
    const transport = sessions.get(sessionId);
    if (!transport) {
      res.statusCode = 404;
      res.end('Session not found');
      return;
    }
    return await transport.handleRequest(req, res);
  }
  if (req.method === 'POST') {
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: () => crypto.randomUUID(),
      onsessioninitialized: sessionId => {
        sessions.set(sessionId, transport);
      }
    });
    transport.onclose = () => {
      if (transport.sessionId)
        sessions.delete(transport.sessionId);
    };
    await server.connect(transport);
    await transport.handleRequest(req, res);
    return;
  }
  res.statusCode = 400;
  res.end('Invalid request');
}

export async function startHttpServer(config) {
  const { host, port } = config;
  const httpServer = http.createServer();
  await new Promise<void>((resolve, reject) => {
    httpServer.on('error', reject);
    httpServer.listen(port, host, () => {
      httpServer.removeListener('error', reject);
      resolve();
    });
  });
  return httpServer;
}

export function startHttpTransport(httpServer, mcpServer) {
  const sseSessions = new Map();
  const streamableSessions = new Map();
  httpServer.on('request', async (req, res) => {
    const timestamp = new Date().toISOString();
    const url = new URL(\`http://localhost\${req.url}\`);
    console.error(\`[\${timestamp}] HTTP Request: \${req.method} \${url.pathname} from \${req.socket.remoteAddress}\`);
    if (url.pathname.startsWith('/sse'))
      await handleSSE(mcpServer, req, res, url, sseSessions);
    else
      await handleStreamable(mcpServer, req, res, streamableSessions);
  });
  const url = httpAddressToString(httpServer.address());
  const message = [
    \`Listening on \${url}\`,
    'Put this in your client config:',
    JSON.stringify({
      'mcpServers': {
        'playwright': {
          'url': \`\${url}/mcp\`
        }
      }
    }, undefined, 2),
    'For legacy SSE transport support, you can use the /sse endpoint instead.',
  ].join('\n');
  console.error(message);
}

export function httpAddressToString(address) {
  assert(address, 'Could not bind server socket');
  if (typeof address === 'string')
    return address;
  const resolvedPort = address.port;
  let resolvedHost = address.family === 'IPv4' ? address.address : \`[\${address.address}]\`;
  if (resolvedHost === '0.0.0.0' || resolvedHost === '[::]')
    resolvedHost = 'localhost';
  return \`http://\${resolvedHost}:\${resolvedPort}\`;
}
EOF

# 2. src/index.ts
cat > "$REPO_DIR/src/index.ts" <<EOF
#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { createToolDefinitions } from "./tools.js";
import { setupRequestHandlers } from "./requestHandler.js";
import { startStdioTransport, startHttpServer, startHttpTransport } from "./transport.js";

function parseArgs() {
  const args = process.argv.slice(2);
  const config = { port: undefined, host: undefined };
  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--port':
        config.port = parseInt(args[++i]);
        break;
      case '--host':
        config.host = args[++i];
        break;
      case '--help':
        console.log(\`Usage: playwright-mcp-server [options]

Options:
  --port <port>    Port to listen on for HTTP transport
  --host <host>    Host to bind server to (default: localhost)
  --help           Show this help message

Examples:
  # Run with stdio transport (default)
  playwright-mcp-server

  # Run with HTTP transport on port 9300
  playwright-mcp-server --port 9300

  # Run with HTTP transport on all interfaces
  playwright-mcp-server --port 9300 --host 0.0.0.0\`);
        process.exit(0);
        break;
    }
  }
  return config;
}

async function runServer() {
  const config = parseArgs();
  const server = new Server(
    { name: "playwright-mcp", version: "1.0.6" },
    { capabilities: { resources: {}, tools: {} } }
  );
  const TOOLS = createToolDefinitions();
  setupRequestHandlers(server, TOOLS);
  function shutdown() {
    console.log('Shutdown signal received');
    process.exit(0);
  }
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
  process.on('exit', shutdown);
  process.on('uncaughtException', (err) => {
    console.error('Uncaught Exception:', err);
  });
  if (config.port !== undefined) {
    const httpServer = await startHttpServer({ host: config.host || 'localhost', port: config.port });
    startHttpTransport(httpServer, server);
  } else {
    await startStdioTransport(server);
  }
}
runServer().catch((error) => {
  console.error("Fatal error in main():", error);
  process.exit(1);
});
EOF

if [ ! -f "$REPO_DIR/../scripts/start-server.sh" ]; then
cat > "$REPO_DIR/../scripts/start-server.sh" <<EOF
#!/bin/bash
PORT=${1:-9300}
HOST=${2:-localhost}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../dist/index.js" ]; then
    EXECUTABLE="$SCRIPT_DIR/../dist/index.js"
else
    echo "Error: Cannot find playwright-mcp-server executable."
    exit 1
fi
echo "Starting Playwright MCP Server on port $PORT ..."
node "$EXECUTABLE" --port "$PORT" --host "$HOST"
EOF
chmod +x scripts/start-server.sh
fi

if [ ! -f "$REPO_DIR/../scripts/test-server.sh" ]; then
cat > "$REPO_DIR/../scripts/test-server.sh" <<EOF
#!/bin/bash
PORT=${1:-9300}
BASE_URL="http://localhost:$PORT"
echo "Testing Playwright MCP Server at $BASE_URL"
curl -s -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' "$BASE_URL/mcp"
EOF
chmod +x scripts/test-server.sh
fi

if [ ! -f "$REPO_DIR/HTTP_SERVER_MODE.md" ]; then
cat > "$REPO_DIR/HTTP_SERVER_MODE.md" <<EOF
# HTTP Server Mode

## Usage

### Stdio Mode (Default)
    npx @executeautomation/playwright-mcp-server

### HTTP Server Mode
    ./scripts/start-server.sh $PORT

### Test Server
    ./scripts/test-server.sh $PORT

## MCP Client Configuration

    npx @executeautomation/playwright-mcp-server --port $PORT

## Endpoints
- /mcp
- /sse
EOF
fi

# Done
echo "\nHTTP server (standalone, /mcp, /sse, CLI, logging, ...) into repo!"
echo "You can run ./scripts/start-server.sh $PORT to test."
