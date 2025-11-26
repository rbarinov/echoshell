import express from 'express';
import { WebSocketServer, WebSocket } from 'ws';
import http from 'http';
import crypto from 'crypto';
import cors from 'cors';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

// Get directory of current module (works with ES modules)
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load .env files in priority order:
// 1. Service-specific .env (tunnel-server/.env) - highest priority
// 2. Root .env (echoshell/.env) - fallback
// 3. System environment variables (already loaded)
const serviceEnvPath = path.resolve(__dirname, '../.env');
const rootEnvPath = path.resolve(__dirname, '../../.env');

// Load service-specific .env first (will override root .env)
if (process.env.DOTENV_CONFIG_PATH) {
  // If explicitly set via environment variable, resolve it (handles relative paths)
  const explicitPath = path.isAbsolute(process.env.DOTENV_CONFIG_PATH)
    ? process.env.DOTENV_CONFIG_PATH
    : path.resolve(process.cwd(), process.env.DOTENV_CONFIG_PATH);
  dotenv.config({ path: explicitPath });
} else {
  // Otherwise, try service-specific, then root
  dotenv.config({ path: serviceEnvPath });
  dotenv.config({ path: rootEnvPath, override: false }); // Don't override service-specific values
}

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

app.use(cors());
app.use(express.json());

// Store active tunnel connections
interface TunnelConnection {
  tunnelId: string;
  apiKey: string;
  name: string;
  ws: WebSocket;
  createdAt: number;
  clientAuthKey?: string;
  lastPongReceived: number;
  pingInterval?: NodeJS.Timeout;
  healthCheckInterval?: NodeJS.Timeout;
}

const tunnels = new Map<string, TunnelConnection>();

// Store pending HTTP requests waiting for tunnel responses
const pendingRequests = new Map<string, express.Response>();

// Store terminal stream connections (iPhone -> tunnel server)
interface StreamConnection {
  ws: WebSocket;
  lastPongReceived: number;
  pingInterval?: NodeJS.Timeout;
  healthCheckInterval?: NodeJS.Timeout;
}

const terminalStreams = new Map<string, Set<StreamConnection>>();
const recordingWsStreams = new Map<string, Set<StreamConnection>>();
const recordingSseStreams = new Map<string, Set<express.Response>>();

// Heartbeat configuration
const PING_INTERVAL_MS = 20000; // 20 seconds
const PONG_TIMEOUT_MS = 30000; // 30 seconds

interface WebSocketMessage {
  type: string;
  requestId?: string;
  statusCode?: number;
  body?: unknown;
}

interface TunnelCreateRequest {
  name?: string;
  tunnel_id?: string;  // Optional: for restoring existing tunnel
}

console.log('🚀 Tunnel Server starting...');

// Load and validate registration API key
const REGISTRATION_API_KEY = process.env.TUNNEL_REGISTRATION_API_KEY;
if (!REGISTRATION_API_KEY) {
  console.error('❌ TUNNEL_REGISTRATION_API_KEY is not set in environment variables');
  console.error('💡 Set it in tunnel-server/.env or pass as environment variable');
  process.exit(1);
}
console.log('🔑 Registration API key configured');

// Log public host configuration at startup
const PORT = parseInt(process.env.PORT || '8000', 10);
const publicHost = process.env.PUBLIC_HOST || process.env.HOST || 'localhost';
const protocol = process.env.PUBLIC_PROTOCOL || 'http';
const wsProtocol = protocol === 'https' ? 'wss' : 'ws';

console.log('🌐 Public Host Configuration:');
console.log(`   Host: ${publicHost}`);
console.log(`   Protocol: ${protocol} (WebSocket: ${wsProtocol})`);
console.log(`   Port: ${PORT}`);

// Determine host for URL construction
let hostForUrl: string;
if (publicHost.includes(':')) {
  hostForUrl = publicHost;
} else if (protocol === 'https') {
  hostForUrl = publicHost;
} else {
  hostForUrl = PORT === 80 ? publicHost : `${publicHost}:${PORT}`;
}

const baseUrl = `${protocol}://${hostForUrl}`;
console.log(`   Base URL: ${baseUrl}`);

// Warn if using localhost (not accessible externally)
if (publicHost === 'localhost' || publicHost === '127.0.0.1') {
  console.warn('⚠️  WARNING: Using localhost as public host');
  console.warn('   This will only work for local connections.');
  console.warn('   For external access, set PUBLIC_HOST to your server\'s public IP or domain name.');
  console.warn('   Example: PUBLIC_HOST=your-server.com or PUBLIC_HOST=123.45.67.89');
}

// Log environment variable sources
const hostSource = process.env.PUBLIC_HOST ? 'PUBLIC_HOST' : (process.env.HOST ? 'HOST' : 'default (localhost)');
const protocolSource = process.env.PUBLIC_PROTOCOL ? 'PUBLIC_PROTOCOL' : 'default (http)';
console.log(`   Configuration source: ${hostSource}, ${protocolSource}`);

// Create new tunnel or restore existing
app.post('/tunnel/create', (req, res) => {
  // Check API key authentication
  const providedApiKey = req.headers['x-api-key'] || req.headers['authorization']?.replace('Bearer ', '');
  
  if (!providedApiKey || providedApiKey !== REGISTRATION_API_KEY) {
    console.log('❌ Unauthorized tunnel registration attempt');
    return res.status(401).json({ 
      error: 'Unauthorized',
      message: 'Valid API key required for tunnel registration'
    });
  }
  
  const body = req.body as TunnelCreateRequest;
  const { name, tunnel_id } = body;
  
  let tunnelId: string;
  let apiKey: string;
  let isRestored = false;
  
  if (tunnel_id) {
    // Restore existing tunnel
    tunnelId = tunnel_id;
    // Generate a new connection API key (different from registration key)
    apiKey = crypto.randomBytes(32).toString('hex');
    isRestored = true;
    console.log(`🔄 Restoring tunnel: ${tunnelId} for ${name}`);
  } else {
    // Create new tunnel
    tunnelId = crypto.randomBytes(8).toString('hex');
    apiKey = crypto.randomBytes(32).toString('hex');
    console.log(`✅ Creating new tunnel: ${tunnelId} for ${name}`);
  }
  
  // Use module-level public host configuration
  const config = {
    tunnelId,
    apiKey,
    publicUrl: `${baseUrl}/api/${tunnelId}`,
    wsUrl: `${wsProtocol}://${hostForUrl}/tunnel/${tunnelId}`,
    isRestored
  };
  
  if (isRestored) {
    console.log(`🔄 Tunnel restored: ${tunnelId} for ${name || 'Unknown'}`);
  } else {
    console.log(`✅ Tunnel created: ${tunnelId} for ${name || 'Unknown'}`);
  }
  console.log(`   Public Host: ${publicHost} (${protocol})`);
  console.log(`   Public URL: ${config.publicUrl}`);
  console.log(`   WebSocket URL: ${config.wsUrl}`);
  
  // Log accessibility info
  if (publicHost === 'localhost' || publicHost === '127.0.0.1') {
    console.warn(`   ⚠️  This tunnel uses localhost and may not be accessible from external devices`);
  } else {
    console.log(`   ✓ Public host configured - tunnel should be accessible externally`);
  }
  
  res.json({ config });
});

// WebSocket endpoint for tunnel connection (laptop connects here)
wss.on('connection', (ws, req) => {
  const url = new URL(req.url!, `http://${req.headers.host}`);
  const pathParts = url.pathname.split('/');
  
  // Handle laptop tunnel connection: /tunnel/:tunnelId
  if (pathParts[1] === 'tunnel' && pathParts[2] && pathParts.length === 3) {
    const tunnelId = pathParts[2];
    const apiKey = url.searchParams.get('api_key');
    
    if (!apiKey) {
      ws.close(1008, 'API key required');
      return;
    }
    
    // Register tunnel connection
    const tunnelConnection: TunnelConnection = {
      tunnelId,
      apiKey,
      name: 'Laptop',
      ws,
      createdAt: Date.now(),
      lastPongReceived: Date.now()
    };
    tunnels.set(tunnelId, tunnelConnection);
    
    console.log(`📡 Tunnel connected: ${tunnelId}`);
    
    // Setup ping/pong heartbeat for tunnel connection
    setupTunnelHeartbeat(tunnelConnection);
    
    ws.on('message', (data) => {
      console.log(`📥📥📥 Tunnel server: WebSocket message received! Data type: ${typeof data}`);
      try {
        const rawMessage = data.toString();
        console.log(`📥📥📥 Tunnel server: Raw message length: ${rawMessage.length} chars`);
        console.log(`📥📥📥 Tunnel server: Raw message (first 200 chars): ${rawMessage.substring(0, 200)}`);
        let message: WebSocketMessage;
        try {
          message = JSON.parse(rawMessage) as WebSocketMessage;
          console.log(`📥📥📥 Tunnel server: Successfully parsed JSON, message.type=${message.type}`);
        } catch (parseError) {
          console.error(`❌❌❌ Tunnel server: Failed to parse WebSocket message: ${parseError}`);
          console.error(`❌❌❌ Tunnel server: Raw message (first 500 chars): ${rawMessage.substring(0, 500)}`);
          return;
        }
        
        // Log all incoming messages for debugging
        if (message.type === 'recording_output') {
          console.log(`📥📥📥 Tunnel server received recording_output message: ${rawMessage.substring(0, 500)}`);
          console.log(`📥📥📥 Tunnel server: Parsed message type=${message.type}, sessionId=${(message as any).sessionId}, isComplete=${(message as any).isComplete}`);
        } else {
          // Log other message types too (but shorter)
          console.log(`📥 Tunnel server: Received WebSocket message type=${message.type}`);
        }
        
        // Handle response to pending HTTP request
        if (message.type === 'http_response' && message.requestId) {
          const res = pendingRequests.get(message.requestId);
          if (res) {
            res.status(message.statusCode || 200).json(message.body);
            pendingRequests.delete(message.requestId);
          }
        }
        
        // Handle client auth key registration
        if (message.type === 'client_auth_key') {
          const key = (message as any).key;
          if (typeof key === 'string' && key.length > 0) {
            const tunnel = tunnels.get(tunnelId);
            if (tunnel) {
              tunnel.clientAuthKey = key;
              console.log(`🔐 Received client auth key for tunnel ${tunnelId}`);
            }
          }
          return;
        }
        
        // Handle terminal output streaming from laptop
        if (message.type === 'terminal_output') {
          const sessionId = (message as any).sessionId;
          const data = (message as any).data;
          const streamKey = `${tunnelId}:${sessionId}`;
          const clients = terminalStreams.get(streamKey);
          
          if (clients) {
            // Broadcast to all connected iPhone clients in the expected format
            const formattedMessage = JSON.stringify({
              type: 'output',
              session_id: sessionId,
              data: data,
              timestamp: Date.now()
            });
            
            clients.forEach(conn => {
              if (conn.ws.readyState === WebSocket.OPEN) {
                conn.ws.send(formattedMessage);
              }
            });
          }
        }

        // Handle recording output streaming from laptop
        if (message.type === 'recording_output') {
          const sessionId = (message as any).sessionId;
          const streamKey = `${tunnelId}:${sessionId}:recording`;
          const wsClients = recordingWsStreams.get(streamKey);
          
          console.log(`📥📥📥 Tunnel server: Processing recording_output for sessionId=${sessionId}, streamKey=${streamKey}`);
          console.log(`📥📥📥 Tunnel server: wsClients=${wsClients ? wsClients.size : 'null'} clients connected`);
          
          // Check if isComplete exists in the message (don't default to false if it's undefined)
          const incomingIsComplete = (message as any).isComplete;
          const hasIsComplete = incomingIsComplete !== undefined && incomingIsComplete !== null;
          
          console.log(`📥📥📥 Tunnel server: incomingIsComplete=${incomingIsComplete}, hasIsComplete=${hasIsComplete}`);
          
          const payload: any = {
            type: 'recording_output',
            session_id: sessionId,
            text: (message as any).text || '',
            delta: (message as any).delta || '',
            raw: (message as any).raw,
            timestamp: (message as any).timestamp ?? Date.now()
          };
          
          // Only include isComplete if it was present in the original message
          if (hasIsComplete) {
            payload.isComplete = incomingIsComplete;
            console.log(`✅✅✅ Tunnel server: Adding isComplete=${incomingIsComplete} to payload`);
          } else {
            console.log(`⚠️⚠️⚠️ Tunnel server: isComplete not present in message, not adding to payload`);
          }
          
          console.log(`📤📤📤 Tunnel server forwarding recording_output: sessionId=${sessionId}, text=${payload.text.length} chars, isComplete=${payload.isComplete ?? 'undefined'}`);
          console.log(`📤📤📤 Tunnel server: Original message.isComplete=${incomingIsComplete}, hasIsComplete=${hasIsComplete}, payload.isComplete=${payload.isComplete ?? 'undefined'}`);
          console.log(`📤📤📤 Tunnel server: Full payload JSON: ${JSON.stringify(payload)}`);
          const payloadString = JSON.stringify(payload);

          if (wsClients && wsClients.size > 0) {
            let sentCount = 0;
            wsClients.forEach(conn => {
              if (conn.ws.readyState === WebSocket.OPEN) {
                conn.ws.send(payloadString);
                sentCount++;
                console.log(`📤📤📤 Tunnel server: Sent to client (${sentCount}/${wsClients.size})`);
              } else {
                console.log(`⚠️⚠️⚠️ Tunnel server: Client WebSocket not OPEN, state=${conn.ws.readyState}`);
              }
            });
            console.log(`📤📤📤 Tunnel server: Total sent to ${sentCount} clients`);
          } else {
            console.log(`⚠️⚠️⚠️ Tunnel server: No clients connected for streamKey=${streamKey}`);
          }

          const sseClients = recordingSseStreams.get(streamKey);
          if (sseClients && sseClients.size > 0) {
            sseClients.forEach((client) => {
              client.write(`event: recording_output\n`);
              client.write(`data: ${payloadString}\n\n`);
            });
          }
        }
      } catch (error: unknown) {
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        console.error('❌ Error processing message:', errorMessage);
      }
    });
    
    ws.on('pong', () => {
      const tunnel = tunnels.get(tunnelId);
      if (tunnel) {
        tunnel.lastPongReceived = Date.now();
      }
    });
    
    ws.on('close', () => {
      const tunnel = tunnels.get(tunnelId);
      if (tunnel) {
        if (tunnel.pingInterval) {
          clearInterval(tunnel.pingInterval);
        }
        if (tunnel.healthCheckInterval) {
          clearInterval(tunnel.healthCheckInterval);
        }
      }
      tunnels.delete(tunnelId);
      console.log(`📡 Tunnel disconnected: ${tunnelId}`);
    });
    
    ws.send(JSON.stringify({ type: 'connected', tunnelId }));
    return;
  }
  
  // Handle iPhone terminal stream connection: /api/:tunnelId/terminal/:sessionId/stream
  if (pathParts[1] === 'api' && pathParts[2] && pathParts[3] === 'terminal' && pathParts[4] && pathParts[5] === 'stream') {
    const tunnelId = pathParts[2];
    const sessionId = pathParts[4];
    const streamKey = `${tunnelId}:${sessionId}`;
    
    console.log(`📱 Terminal stream connected: ${streamKey}`);
    
    // Register stream client
    if (!terminalStreams.has(streamKey)) {
      terminalStreams.set(streamKey, new Set());
    }
    const streamConnection: StreamConnection = {
      ws,
      lastPongReceived: Date.now()
    };
    terminalStreams.get(streamKey)!.add(streamConnection);
    
    // Setup ping/pong heartbeat for terminal stream
    setupStreamHeartbeat(streamKey, streamConnection, terminalStreams);
    
    // Handle input from iPhone
    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString()) as { type: string; data?: string };
        
        // Forward input to laptop via tunnel
        if (message.type === 'input') {
          const tunnel = tunnels.get(tunnelId);
          if (tunnel && tunnel.ws.readyState === WebSocket.OPEN) {
            tunnel.ws.send(JSON.stringify({
              type: 'terminal_input',
              sessionId,
              data: message.data
            }));
          }
        }
      } catch (error) {
        console.error('❌ Error processing stream message:', error);
      }
    });
    
    ws.on('pong', () => {
      streamConnection.lastPongReceived = Date.now();
    });
    
    ws.on('close', () => {
      console.log(`📱 Terminal stream disconnected: ${streamKey}`);
      if (streamConnection.pingInterval) {
        clearInterval(streamConnection.pingInterval);
      }
      if (streamConnection.healthCheckInterval) {
        clearInterval(streamConnection.healthCheckInterval);
      }
      terminalStreams.get(streamKey)?.delete(streamConnection);
      if (terminalStreams.get(streamKey)?.size === 0) {
        terminalStreams.delete(streamKey);
      }
    });
    
    return;
  }

  // Handle recording stream connection: /api/:tunnelId/recording/:sessionId/stream
  if (pathParts[1] === 'api' && pathParts[2] && pathParts[3] === 'recording' && pathParts[4] && pathParts[5] === 'stream') {
    const tunnelId = pathParts[2];
    const sessionId = pathParts[4];
    const streamKey = `${tunnelId}:${sessionId}:recording`;

    console.log(`🎙️ Recording stream connected: ${streamKey}`);

    if (!recordingWsStreams.has(streamKey)) {
      recordingWsStreams.set(streamKey, new Set());
    }
    const recordingConnection: StreamConnection = {
      ws,
      lastPongReceived: Date.now()
    };
    recordingWsStreams.get(streamKey)!.add(recordingConnection);
    
    // Setup ping/pong heartbeat for recording stream
    setupStreamHeartbeat(streamKey, recordingConnection, recordingWsStreams);

    ws.on('pong', () => {
      recordingConnection.lastPongReceived = Date.now();
    });
    
    ws.on('close', () => {
      console.log(`🎙️ Recording stream disconnected: ${streamKey}`);
      if (recordingConnection.pingInterval) {
        clearInterval(recordingConnection.pingInterval);
      }
      if (recordingConnection.healthCheckInterval) {
        clearInterval(recordingConnection.healthCheckInterval);
      }
      recordingWsStreams.get(streamKey)?.delete(recordingConnection);
      if (recordingWsStreams.get(streamKey)?.size === 0) {
        recordingWsStreams.delete(streamKey);
      }
    });

    return;
  }
  
  // Unknown WebSocket path
  ws.close(1008, 'Invalid WebSocket path');
});

// SSE endpoint for recording stream
app.get('/api/:tunnelId/recording/:sessionId/events', (req, res) => {
  const { tunnelId, sessionId } = req.params;
  const tunnel = tunnels.get(tunnelId);

  if (!tunnel) {
    return res.status(404).json({ error: 'Tunnel not found or not connected' });
  }

  if (!tunnel.clientAuthKey) {
    return res.status(503).json({ error: 'Tunnel auth key not registered yet' });
  }

  const providedKey = req.header('X-Laptop-Auth-Key');
  if (!providedKey || providedKey !== tunnel.clientAuthKey) {
    return res.status(401).json({ error: 'Unauthorized: Invalid or missing X-Laptop-Auth-Key header' });
  }

  const streamKey = `${tunnelId}:${sessionId}:recording`;
  console.log(`🎙️ SSE recording stream connected: ${streamKey}`);

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no');
  req.socket.setTimeout(0);
  req.socket.setKeepAlive(true);
  res.write('\n');

  if (!recordingSseStreams.has(streamKey)) {
    recordingSseStreams.set(streamKey, new Set());
  }
  recordingSseStreams.get(streamKey)!.add(res);

  req.on('close', () => {
    console.log(`🎙️ SSE recording stream disconnected: ${streamKey}`);
    res.end();
    recordingSseStreams.get(streamKey)?.delete(res);
    if (recordingSseStreams.get(streamKey)?.size === 0) {
      recordingSseStreams.delete(streamKey);
    }
  });
});

// Proxy HTTP requests to connected laptop
app.all('/api/:tunnelId/*', async (req, res) => {
  const { tunnelId } = req.params;
  
  // Extract the path after /api/:tunnelId/
  // req.path is like /api/2714291ef08b4006/keys/request
  // We want to extract /keys/request
  const fullPath = req.path;
  const prefix = `/api/${tunnelId}`;
  
  // Remove the prefix and ensure we have a valid path
  let path = fullPath.startsWith(prefix) 
    ? fullPath.slice(prefix.length) 
    : fullPath.replace(`/api/${tunnelId}`, '');
  
  // Normalize path: ensure it starts with / and doesn't have double slashes
  if (!path || path === '') {
    path = '/';
  } else if (!path.startsWith('/')) {
    path = '/' + path;
  }
  
  // Remove any double slashes (except at the start)
  path = path.replace(/\/+/g, '/');
  
  console.log(`📥 Proxy: ${req.method} ${fullPath} -> ${path}`);
  
  const tunnel = tunnels.get(tunnelId);
  
  if (!tunnel) {
    return res.status(404).json({ error: 'Tunnel not found or not connected' });
  }
  
  const requestId = crypto.randomBytes(8).toString('hex');
  
  // Store response handler
  pendingRequests.set(requestId, res);
  
  // Forward request to laptop via WebSocket
  tunnel.ws.send(JSON.stringify({
    type: 'http_request',
    requestId,
    method: req.method,
    path: path,
    headers: req.headers,
    body: req.body,
    query: req.query
  }));
  
  // Timeout after 30 seconds
  setTimeout(() => {
    if (pendingRequests.has(requestId)) {
      pendingRequests.delete(requestId);
      res.status(504).json({ error: 'Gateway timeout' });
    }
  }, 30000);
});

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    tunnels: tunnels.size,
    uptime: process.uptime()
  });
});

// Setup heartbeat functions
function setupTunnelHeartbeat(tunnel: TunnelConnection): void {
  // Send periodic pings
  tunnel.pingInterval = setInterval(() => {
    if (tunnel.ws.readyState === WebSocket.OPEN) {
      tunnel.ws.ping();
    }
  }, PING_INTERVAL_MS);
  
  // Check for dead connections
  tunnel.healthCheckInterval = setInterval(() => {
    const tunnelConnection = tunnels.get(tunnel.tunnelId);
    if (!tunnelConnection) {
      if (tunnel.healthCheckInterval) {
        clearInterval(tunnel.healthCheckInterval);
      }
      return;
    }
    
    const timeSinceLastPong = Date.now() - tunnelConnection.lastPongReceived;
    if (timeSinceLastPong > PONG_TIMEOUT_MS) {
      console.log(`⚠️ Tunnel ${tunnel.tunnelId} appears dead (no pong for ${timeSinceLastPong}ms), closing...`);
      if (tunnelConnection.pingInterval) {
        clearInterval(tunnelConnection.pingInterval);
      }
      if (tunnelConnection.healthCheckInterval) {
        clearInterval(tunnelConnection.healthCheckInterval);
      }
      tunnelConnection.ws.terminate();
      tunnels.delete(tunnel.tunnelId);
    }
  }, PONG_TIMEOUT_MS);
}

function setupStreamHeartbeat(
  streamKey: string,
  connection: StreamConnection,
  streamMap: Map<string, Set<StreamConnection>>
): void {
  // Send periodic pings
  connection.pingInterval = setInterval(() => {
    if (connection.ws.readyState === WebSocket.OPEN) {
      connection.ws.ping();
    }
  }, PING_INTERVAL_MS);
  
  // Check for dead connections
  connection.healthCheckInterval = setInterval(() => {
    const connections = streamMap.get(streamKey);
    if (!connections || !connections.has(connection)) {
      if (connection.healthCheckInterval) {
        clearInterval(connection.healthCheckInterval);
      }
      return;
    }
    
    const timeSinceLastPong = Date.now() - connection.lastPongReceived;
    if (timeSinceLastPong > PONG_TIMEOUT_MS) {
      console.log(`⚠️ Stream ${streamKey} appears dead (no pong for ${timeSinceLastPong}ms), closing...`);
      if (connection.pingInterval) {
        clearInterval(connection.pingInterval);
      }
      if (connection.healthCheckInterval) {
        clearInterval(connection.healthCheckInterval);
      }
      connection.ws.terminate();
      connections.delete(connection);
      if (connections.size === 0) {
        streamMap.delete(streamKey);
      }
    }
  }, PONG_TIMEOUT_MS);
}

server.listen(PORT, () => {
  console.log(`✅ Tunnel Server running on port ${PORT}`);
  console.log(`📡 WebSocket server ready`);
  console.log(`🌐 HTTP endpoint: http://localhost:${PORT}`);
  console.log(`🌐 Public endpoint: ${baseUrl}`);
  console.log(`💓 Heartbeat: ping every ${PING_INTERVAL_MS}ms, timeout ${PONG_TIMEOUT_MS}ms`);
});
