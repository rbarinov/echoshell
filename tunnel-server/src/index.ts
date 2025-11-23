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
}

const tunnels = new Map<string, TunnelConnection>();

// Store pending HTTP requests waiting for tunnel responses
const pendingRequests = new Map<string, express.Response>();

// Store terminal stream connections (iPhone -> tunnel server)
const terminalStreams = new Map<string, Set<WebSocket>>();

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
  
  // Get public URL from environment or use localhost as fallback
  const port = process.env.PORT || 8000;
  const publicHost = process.env.PUBLIC_HOST || process.env.HOST || 'localhost';
  const protocol = process.env.PUBLIC_PROTOCOL || (publicHost === 'localhost' ? 'http' : 'https');
  const wsProtocol = process.env.PUBLIC_PROTOCOL === 'https' ? 'wss' : 'ws';
  
  const baseUrl = `${protocol}://${publicHost}${publicHost.includes(':') ? '' : `:${port}`}`;
  
  const config = {
    tunnelId,
    apiKey,
    publicUrl: `${baseUrl}/api/${tunnelId}`,
    wsUrl: `${wsProtocol}://${publicHost}${publicHost.includes(':') ? '' : `:${port}`}/tunnel/${tunnelId}`,
    isRestored
  };
  
  if (isRestored) {
    console.log(`🔄 Tunnel restored: ${tunnelId} for ${name}`);
  } else {
    console.log(`✅ Tunnel created: ${tunnelId} for ${name}`);
  }
  console.log(`   Public URL: ${config.publicUrl}`);
  console.log(`   WebSocket URL: ${config.wsUrl}`);
  
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
    tunnels.set(tunnelId, {
      tunnelId,
      apiKey,
      name: 'Laptop',
      ws,
      createdAt: Date.now()
    });
    
    console.log(`📡 Tunnel connected: ${tunnelId}`);
    
    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString()) as WebSocketMessage;
        
        // Handle response to pending HTTP request
        if (message.type === 'http_response' && message.requestId) {
          const res = pendingRequests.get(message.requestId);
          if (res) {
            res.status(message.statusCode || 200).json(message.body);
            pendingRequests.delete(message.requestId);
          }
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
            
            clients.forEach(client => {
              if (client.readyState === WebSocket.OPEN) {
                client.send(formattedMessage);
              }
            });
          }
        }
      } catch (error: unknown) {
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        console.error('❌ Error processing message:', errorMessage);
      }
    });
    
    ws.on('close', () => {
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
    terminalStreams.get(streamKey)!.add(ws);
    
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
    
    ws.on('close', () => {
      console.log(`📱 Terminal stream disconnected: ${streamKey}`);
      terminalStreams.get(streamKey)?.delete(ws);
      if (terminalStreams.get(streamKey)?.size === 0) {
        terminalStreams.delete(streamKey);
      }
    });
    
    return;
  }
  
  // Unknown WebSocket path
  ws.close(1008, 'Invalid WebSocket path');
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

const PORT = process.env.PORT || 8000;
server.listen(PORT, () => {
  console.log(`✅ Tunnel Server running on port ${PORT}`);
  console.log(`📡 WebSocket server ready`);
  console.log(`🌐 HTTP endpoint: http://localhost:${PORT}`);
});
