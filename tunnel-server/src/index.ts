import express from 'express';
import { WebSocketServer, WebSocket } from 'ws';
import http from 'http';
import crypto from 'crypto';
import cors from 'cors';

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

console.log('🚀 Tunnel Server starting...');

// Create new tunnel
app.post('/tunnel/create', (req, res) => {
  const { name } = req.body;
  
  const tunnelId = crypto.randomBytes(8).toString('hex');
  const apiKey = crypto.randomBytes(32).toString('hex');
  
  const config = {
    tunnelId,
    apiKey,
    publicUrl: `http://localhost:${process.env.PORT || 8000}/api/${tunnelId}`,
    wsUrl: `ws://localhost:${process.env.PORT || 8000}/tunnel/${tunnelId}`
  };
  
  console.log(`✅ Tunnel created: ${tunnelId} for ${name}`);
  
  res.json({ config });
});

// WebSocket endpoint for tunnel connection (laptop connects here)
wss.on('connection', (ws, req) => {
  const url = new URL(req.url!, `http://${req.headers.host}`);
  const pathParts = url.pathname.split('/');
  
  if (pathParts[1] === 'tunnel' && pathParts[2]) {
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
        const message = JSON.parse(data.toString());
        
        // Handle response to pending HTTP request
        if (message.type === 'http_response' && message.requestId) {
          const res = pendingRequests.get(message.requestId);
          if (res) {
            res.status(message.statusCode || 200).json(message.body);
            pendingRequests.delete(message.requestId);
          }
        }
      } catch (error) {
        console.error('❌ Error processing message:', error);
      }
    });
    
    ws.on('close', () => {
      tunnels.delete(tunnelId);
      console.log(`📡 Tunnel disconnected: ${tunnelId}`);
    });
    
    ws.send(JSON.stringify({ type: 'connected', tunnelId }));
  }
});

// Proxy HTTP requests to connected laptop
app.all('/api/:tunnelId/*', async (req, res) => {
  const { tunnelId } = req.params;
  const path = req.params[0];
  
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
    path: '/' + path,
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
