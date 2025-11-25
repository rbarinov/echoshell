import express from 'express';
import { WebSocket, WebSocketServer } from 'ws';
import { createServer } from 'http';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import QRCode from 'qrcode';
import { TerminalManager } from './terminal/TerminalManager.js';
import { KeyManager } from './keys/KeyManager.js';
import { TunnelClient } from './tunnel/TunnelClient.js';
import { AIAgent } from './agent/AIAgent.js';
import { StateManager } from './storage/StateManager.js';
import { RecordingStreamManager } from './output/RecordingStreamManager.js';
import { createLLMProvider } from './agent/LLMProvider.js';
import { createSTTProvider } from './keys/STTProvider.js';
import { createTTSProvider } from './keys/TTSProvider.js';
import { transcribeAudio } from './proxy/STTProxy.js';
import { synthesizeSpeech } from './proxy/TTSProxy.js';
import { WorkspaceManager } from './workspace/WorkspaceManager.js';
import { WorktreeManager } from './workspace/WorktreeManager.js';

// Get directory of current module (works with ES modules)
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load .env files in priority order:
// 1. Service-specific .env (laptop-app/.env) - highest priority
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
app.use(express.json());

// Create HTTP server for WebSocket support
const server = createServer(app);

// Initialize components
const stateManager = new StateManager();
const terminalManager = new TerminalManager(stateManager);

// Initialize providers
const llmProvider = createLLMProvider();
const sttProvider = createSTTProvider();
const ttsProvider = createTTSProvider();

// Initialize managers with providers
const keyManager = new KeyManager(sttProvider, ttsProvider);
const aiAgent = new AIAgent(llmProvider);
const workspaceManager = new WorkspaceManager();
const worktreeManager = new WorktreeManager(workspaceManager);

// Set workspace and worktree managers on AI agent
aiAgent.setWorkspaceManager(workspaceManager);
aiAgent.setWorktreeManager(worktreeManager);

const ALLOWED_TERMINAL_TYPES = ['regular', 'cursor_agent', 'cursor_cli', 'claude_cli'] as const;
type AllowedTerminalType = (typeof ALLOWED_TERMINAL_TYPES)[number];

function isAllowedTerminalType(value: unknown): value is AllowedTerminalType {
  return typeof value === 'string' && (ALLOWED_TERMINAL_TYPES as readonly string[]).includes(value);
}

// Localhost-only web interface
const WEB_PORT = parseInt(process.env.WEB_INTERFACE_PORT || '8002', 10);
const publicDir = path.resolve(__dirname, '../public');

// Middleware to restrict access to localhost only
const localhostOnly = (req: express.Request, res: express.Response, next: express.NextFunction) => {
  const clientIp = req.ip || req.socket.remoteAddress || '';
  const isLocalhost = clientIp === '127.0.0.1' || 
                      clientIp === '::1' || 
                      clientIp === '::ffff:127.0.0.1' ||
                      req.hostname === 'localhost' ||
                      req.hostname === '127.0.0.1';
  
  if (!isLocalhost) {
    return res.status(403).json({ error: 'Access denied. Web interface is only available on localhost.' });
  }
  
  next();
};

// Apply localhost restriction to all routes
app.use(localhostOnly);

// Serve static files (localhost only)
app.use(express.static(publicDir));

// API endpoints for web interface (localhost only)
app.get('/terminal/list', async (_req, res) => {
  try {
    const sessions = terminalManager.listSessions();
    res.json({
      sessions: sessions.map(s => ({
        session_id: s.sessionId,
        working_dir: s.workingDir,
        terminal_type: s.terminalType,
        name: s.name,
        created_at: s.createdAt || Date.now()
      }))
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to list sessions' });
  }
});

app.post('/terminal/create', async (req, res) => {
  try {
    const { terminal_type, working_dir, name } = req.body;
    if (!isAllowedTerminalType(terminal_type)) {
      return res.status(400).json({ error: `terminal_type must be one of: ${ALLOWED_TERMINAL_TYPES.join(', ')}` });
    }
    const session = await terminalManager.createSession(terminal_type, working_dir, name);
    res.json({
      session_id: session.sessionId,
      working_dir: session.workingDir,
      terminal_type: session.terminalType,
      name: session.name,
      status: 'created'
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to create session' });
  }
});

app.get('/terminal/:sessionId/history', (req, res) => {
  try {
    const { sessionId } = req.params;
    const history = terminalManager.getHistory(sessionId);
    res.json({
      session_id: sessionId,
      history
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to get history' });
  }
});

app.post('/terminal/:sessionId/execute', async (req, res) => {
  try {
    const { sessionId } = req.params;
    const { command } = req.body;
    console.log(`🌐 [Express] POST /terminal/${sessionId}/execute - Command: ${JSON.stringify(command)}`);
    const output = await terminalManager.executeCommand(sessionId, command || '');
    res.json({
      session_id: sessionId,
      command,
      output
    });
  } catch (error) {
    console.error(`❌ [Express] Error executing command:`, error);
    res.status(500).json({ error: 'Failed to execute command' });
  }
});

app.post('/terminal/:sessionId/rename', (req, res) => {
  try {
    const { sessionId } = req.params;
    const { name } = req.body;
    if (!name || typeof name !== 'string') {
      return res.status(400).json({ error: 'name is required and must be a string' });
    }
    terminalManager.renameSession(sessionId, name);
    res.json({
      session_id: sessionId,
      name,
      status: 'renamed'
    });
  } catch (error) {
    if (error instanceof Error && error.message === 'Session not found') {
      return res.status(404).json({ error: 'Session not found' });
    }
    res.status(500).json({ error: 'Failed to rename session' });
  }
});

app.delete('/terminal/:sessionId', async (req, res) => {
  try {
    const { sessionId } = req.params;
    await terminalManager.destroySession(sessionId);
    res.json({
      session_id: sessionId,
      status: 'deleted'
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to delete session' });
  }
});

// Workspace management endpoints (localhost only)
app.get('/workspace/list', async (_req, res) => {
  try {
    const workspaces = await workspaceManager.listWorkspaces();
    res.json({
      workspaces: workspaces.map(w => ({
        name: w.name,
        path: w.path,
        created_at: w.createdAt
      }))
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to list workspaces' });
  }
});

app.post('/workspace/create', async (req, res) => {
  try {
    const { workspace_name } = req.body;
    if (!workspace_name || typeof workspace_name !== 'string') {
      return res.status(400).json({ error: 'workspace_name is required and must be a string' });
    }
    const workspace = await workspaceManager.createWorkspace(workspace_name);
    res.json({
      name: workspace.name,
      path: workspace.path,
      created_at: workspace.createdAt,
      status: 'created'
    });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    res.status(500).json({ error: errorMessage });
  }
});

app.delete('/workspace/:workspace', async (req, res) => {
  try {
    const { workspace } = req.params;
    await workspaceManager.removeWorkspace(workspace);
    res.json({
      workspace,
      status: 'deleted'
    });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    res.status(500).json({ error: errorMessage });
  }
});

app.post('/workspace/:workspace/clone', async (req, res) => {
  try {
    const { workspace } = req.params;
    const { repo_url, repo_name } = req.body;
    if (!repo_url || typeof repo_url !== 'string') {
      return res.status(400).json({ error: 'repo_url is required and must be a string' });
    }
    const repo = await workspaceManager.cloneRepository(workspace, repo_url, repo_name);
    res.json({
      name: repo.name,
      path: repo.path,
      remote_url: repo.remoteUrl,
      cloned_at: repo.clonedAt,
      status: 'cloned'
    });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    res.status(500).json({ error: errorMessage });
  }
});

app.get('/workspace/:workspace/repos', async (req, res) => {
  try {
    const { workspace } = req.params;
    const repos = await workspaceManager.listRepositories(workspace);
    res.json({
      workspace,
      repositories: repos.map(r => ({
        name: r.name,
        path: r.path,
        remote_url: r.remoteUrl,
        cloned_at: r.clonedAt
      }))
    });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    res.status(500).json({ error: errorMessage });
  }
});

// Worktree management endpoints (localhost only)
app.post('/workspace/:workspace/:repo/worktree/create', async (req, res) => {
  try {
    const { workspace, repo } = req.params;
    const { branch_or_feature, worktree_name } = req.body;
    if (!branch_or_feature || typeof branch_or_feature !== 'string') {
      return res.status(400).json({ error: 'branch_or_feature is required and must be a string' });
    }
    const worktree = await worktreeManager.createWorktree(workspace, repo, branch_or_feature, worktree_name);
    res.json({
      name: worktree.name,
      path: worktree.path,
      branch: worktree.branch,
      created_at: worktree.createdAt,
      status: 'created'
    });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    res.status(500).json({ error: errorMessage });
  }
});

app.get('/workspace/:workspace/:repo/worktrees', async (req, res) => {
  try {
    const { workspace, repo } = req.params;
    const worktrees = await worktreeManager.listWorktrees(workspace, repo);
    res.json({
      workspace,
      repo,
      worktrees: worktrees.map(w => ({
        name: w.name,
        path: w.path,
        branch: w.branch,
        created_at: w.createdAt
      }))
    });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    res.status(500).json({ error: errorMessage });
  }
});

app.delete('/workspace/:workspace/:repo/worktree/:name', async (req, res) => {
  try {
    const { workspace, repo, name } = req.params;
    await worktreeManager.removeWorktree(workspace, repo, name);
    res.json({
      workspace,
      repo,
      worktree: name,
      status: 'deleted'
    });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    res.status(500).json({ error: errorMessage });
  }
});

app.get('/workspace/:workspace/:repo/worktree/:name/path', (req, res) => {
  try {
    const { workspace, repo, name } = req.params;
    const worktreePath = worktreeManager.getWorktreePath(workspace, repo, name);
    res.json({
      workspace,
      repo,
      worktree: name,
      path: worktreePath
    });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    res.status(500).json({ error: errorMessage });
  }
});

// WebSocket server for terminal streaming (localhost only)
const wss = new WebSocketServer({ server });

wss.on('connection', (ws, req) => {
  // Check if connection is from localhost
  const clientIp = req.socket.remoteAddress || '';
  const isLocalhost = clientIp === '127.0.0.1' || 
                      clientIp === '::1' || 
                      clientIp === '::ffff:127.0.0.1';
  
  if (!isLocalhost) {
    console.warn(`⚠️  WebSocket connection rejected from non-localhost: ${clientIp}`);
    ws.close(1008, 'Access denied. WebSocket is only available on localhost.');
    return;
  }
  
  // Extract session ID from path
  const url = new URL(req.url || '', 'http://localhost');
  const sessionIdMatch = url.pathname.match(/\/terminal\/([^\/]+)\/stream/);
  
  if (!sessionIdMatch) {
    ws.close(1008, 'Invalid session ID');
    return;
  }
  
  const sessionId = sessionIdMatch[1];
  console.log(`📡 WebSocket connected for session: ${sessionId}`);
  
  // Add output listener for this WebSocket
  const outputListener = (data: string) => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({
        type: 'output',
        session_id: sessionId,
        data: data,
        timestamp: Date.now()
      }));
    }
  };
  
  terminalManager.addOutputListener(sessionId, outputListener);
  
  // Handle input from web interface
  ws.on('message', (data) => {
    try {
      const message = JSON.parse(data.toString()) as { type: string; data?: string };
      
      if (message.type === 'input' && message.data) {
        terminalManager.writeInput(sessionId, message.data);
      }
    } catch (error) {
      console.error('❌ Error processing WebSocket message:', error);
    }
  });
  
  ws.on('close', () => {
    console.log(`📡 WebSocket disconnected for session: ${sessionId}`);
    terminalManager.removeOutputListener(sessionId, outputListener);
  });
  
  ws.on('error', (error) => {
    console.error(`❌ WebSocket error for session ${sessionId}:`, error);
  });
});

import type { TunnelConfig } from './tunnel/TunnelClient.js';

interface TunnelRequest {
  method: string;
  path: string;
  body: unknown;
  query: Record<string, string | undefined>;
  headers: Record<string, string | string[] | undefined>;
}

interface TunnelResponse {
  statusCode: number;
  body: unknown;
}

let tunnelClient: TunnelClient | null = null;
let tunnelConfig: TunnelConfig | null = null;
let reconnectAttempt = 0;
const maxReconnectAttempts = 10;

// Recording stream manager - initialized but may not be used in all scenarios
const _recordingStreamManager = new RecordingStreamManager(
  terminalManager,
  () => tunnelClient
);

console.log('🚀 Laptop Application starting...');

// Initialize tunnel connection with retry logic
async function initializeTunnel(isRetry = false): Promise<void> {
  const tunnelUrl = process.env.TUNNEL_SERVER_URL;
  const registrationApiKey = process.env.TUNNEL_REGISTRATION_API_KEY;
  
  if (!tunnelUrl) {
    console.error('❌ TUNNEL_SERVER_URL is not set in environment variables');
    console.log('💡 Please set TUNNEL_SERVER_URL in laptop-app/.env or root .env');
    process.exit(1);
  }
  
  if (!registrationApiKey) {
    console.error('❌ TUNNEL_REGISTRATION_API_KEY is not set in environment variables');
    console.log('💡 Please set TUNNEL_REGISTRATION_API_KEY in laptop-app/.env or root .env');
    console.log('💡 This key must match the tunnel server\'s TUNNEL_REGISTRATION_API_KEY');
    process.exit(1);
  }
  
  try {
    if (isRetry) {
      console.log(`🔄 Retry attempt ${reconnectAttempt}/${maxReconnectAttempts} to connect to tunnel server...`);
    } else {
      console.log(`📡 Connecting to tunnel server: ${tunnelUrl}`);
    }
    
    // Try to load existing tunnel state
    const existingState = await stateManager.loadTunnelState();
    
    const requestBody: { name: string; tunnel_id?: string } = {
      name: process.env.LAPTOP_NAME || 'My Laptop'
    };
    
    // If we have existing state, try to restore the same tunnel ID
    if (existingState) {
      requestBody.tunnel_id = existingState.tunnelId;
      console.log(`🔄 Attempting to restore tunnel: ${existingState.tunnelId}`);
    }
    
    const response = await fetch(`${tunnelUrl}/tunnel/create`, {
      method: 'POST',
      headers: { 
        'Content-Type': 'application/json',
        'X-API-Key': registrationApiKey  // Authentication
      },
      body: JSON.stringify(requestBody)
    });
    
    if (!response.ok) {
      if (response.status === 401) {
        console.error('❌ Unauthorized: Invalid TUNNEL_REGISTRATION_API_KEY');
        console.log('💡 Make sure TUNNEL_REGISTRATION_API_KEY matches the tunnel server');
        process.exit(1);
      }
      throw new Error(`Tunnel server returned status ${response.status}`);
    }
    
    const data = await response.json() as { config: TunnelConfig & { isRestored?: boolean } };
    tunnelConfig = data.config;
    
    if (data.config.isRestored) {
      console.log('🔄 Tunnel restored with existing ID:');
    } else {
      console.log('✅ New tunnel created:');
    }
    console.log(`   Tunnel ID: ${tunnelConfig.tunnelId}`);
    console.log(`   Public URL: ${tunnelConfig.publicUrl}`);
    
    // Save tunnel state for future restarts
    await stateManager.saveTunnelState({
      tunnelId: tunnelConfig.tunnelId,
      apiKey: tunnelConfig.apiKey,
      publicUrl: tunnelConfig.publicUrl,
      wsUrl: tunnelConfig.wsUrl,
      createdAt: Date.now(),
      laptopName: process.env.LAPTOP_NAME || 'My Laptop'
    });
    
    console.log(`💾 Tunnel state saved to: ${stateManager.getStateFilePath()}`);
    
    // Get laptop auth key from environment
    const laptopAuthKey = process.env.LAPTOP_AUTH_KEY;
    if (!laptopAuthKey) {
      console.error('❌ LAPTOP_AUTH_KEY is not set in environment variables');
      console.log('💡 Please set LAPTOP_AUTH_KEY in laptop-app/.env or root .env');
      console.log('💡 Generate a secure key: openssl rand -hex 32');
      process.exit(1);
    }
    
    // Generate and display QR code
    const qrData = JSON.stringify({
      tunnelId: tunnelConfig.tunnelId,
      tunnelUrl: tunnelConfig.publicUrl.replace('/api/' + tunnelConfig.tunnelId, ''),
      wsUrl: tunnelConfig.wsUrl.replace('/tunnel/' + tunnelConfig.tunnelId, ''),
      keyEndpoint: `${tunnelConfig.publicUrl}/keys/request`,
      authKey: laptopAuthKey  // Include auth key in QR code
    });
    
    const qrCodeText = await QRCode.toString(qrData, { type: 'terminal', small: true });
    console.log('\n📱 Scan this QR code with your iPhone:\n');
    console.log(qrCodeText);
    console.log('\n');
    
    // Connect to tunnel
    tunnelClient = new TunnelClient(tunnelConfig, handleTunnelRequest, process.env.LAPTOP_AUTH_KEY);
    await tunnelClient.connect();
    
    // Set up terminal input handler
    tunnelClient.setTerminalInputHandler((sessionId, data) => {
      console.log(`⌨️  Terminal input for ${sessionId}: ${data.length} bytes`);
      terminalManager.writeInput(sessionId, data);
    });
    
    // Set up terminal output streaming
    terminalManager.setTunnelClient(tunnelClient);
    
    // Restore terminal sessions from previous run
    await terminalManager.restoreSessions();
    
    // Reset retry counter on success
    reconnectAttempt = 0;
    
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    
    if (reconnectAttempt === 0) {
      console.error('❌ Failed to connect to tunnel server');
      console.error(`   Error: ${errorMessage}`);
      console.log('\n💡 Possible reasons:');
      console.log('   1. Tunnel server is not running');
      console.log('   2. Incorrect TUNNEL_SERVER_URL in .env');
      console.log('   3. Network connectivity issues');
      console.log('\n🔧 To start tunnel server:');
      console.log('   cd tunnel-server && npm start\n');
    }
    
    // Retry with exponential backoff
    if (reconnectAttempt < maxReconnectAttempts) {
      reconnectAttempt++;
      const delay = Math.min(1000 * Math.pow(2, reconnectAttempt - 1), 30000); // Max 30s
      console.log(`⏳ Retrying in ${delay / 1000}s... (${reconnectAttempt}/${maxReconnectAttempts})`);
      
      setTimeout(() => {
        initializeTunnel(true);
      }, delay);
    } else {
      console.error(`\n❌ Failed to connect after ${maxReconnectAttempts} attempts`);
      console.error('   Please ensure tunnel server is running and try again');
      console.log('\n💡 Run this command in a separate terminal:');
      console.log('   cd tunnel-server && npm start\n');
      process.exit(1);
    }
  }
}

// Validate laptop auth key from request headers
function validateAuthKey(headers: Record<string, string | string[] | undefined>): boolean {
  const expectedKey = process.env.LAPTOP_AUTH_KEY;
  if (!expectedKey) {
    console.error('❌ LAPTOP_AUTH_KEY not configured');
    return false;
  }
  
  // Get auth key from header (case-insensitive)
  const authHeader = Object.entries(headers).find(([key]) => 
    key.toLowerCase() === 'x-laptop-auth-key'
  );
  
  if (!authHeader) {
    console.log('⚠️  Missing X-Laptop-Auth-Key header');
    return false;
  }
  
  const providedKey = Array.isArray(authHeader[1]) ? authHeader[1][0] : authHeader[1];
  
  if (providedKey !== expectedKey) {
    console.log('⚠️  Invalid auth key provided');
    return false;
  }
  
  return true;
}

// Handle incoming HTTP requests from tunnel
async function handleTunnelRequest(req: TunnelRequest): Promise<TunnelResponse> {
  const { method, path, body, query, headers } = req;
  
  console.log(`📥 ${method} ${path}`);
  
  // Validate auth key for ALL requests (including key requests)
  // All requests from iPhone to laptop must include LAPTOP_AUTH_KEY
  if (!validateAuthKey(headers)) {
    return { 
      statusCode: 401, 
      body: { error: 'Unauthorized: Invalid or missing X-Laptop-Auth-Key header' } 
    };
  }
  
  try {
    // Route to appropriate handler
    if (path.startsWith('/keys/')) {
      return handleKeyRequest(method, path, body, query, headers);
    } else if (path.startsWith('/terminal/')) {
      return await handleTerminalRequest(method, path, body, query, headers);
    } else if (path.startsWith('/agent/')) {
      return await handleAgentRequest(method, path, body, headers);
    } else if (path.startsWith('/proxy/stt/')) {
      return await handleSTTProxyRequest(method, path, body, headers);
    } else if (path.startsWith('/proxy/tts/')) {
      return await handleTTSProxyRequest(method, path, body, headers);
    } else if (path.startsWith('/workspace/')) {
      return await handleWorkspaceRequest(method, path, body, query, headers);
    } else if (path === '/tunnel-status' && method === 'GET') {
      return handleTunnelStatusRequest();
    } else {
      return { statusCode: 404, body: { error: 'Not found' } };
    }
  } catch (error: unknown) {
    console.error('❌ Request error:', error);
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    return { statusCode: 500, body: { error: errorMessage } };
  }
}

// Key management endpoints
function handleKeyRequest(method: string, path: string, body: unknown, query: Record<string, string | undefined>, _headers: Record<string, string | string[] | undefined>): TunnelResponse {
  if (path === '/keys/request' && method === 'POST') {
    const bodyObj = body as { device_id?: string; tunnel_id?: string; duration_seconds?: number; permissions?: string[] };
    const { device_id, duration_seconds, permissions } = bodyObj;
    if (!device_id) {
      return { statusCode: 400, body: { error: 'device_id is required' } };
    }
    const keys = keyManager.issueEphemeralKeys(device_id, duration_seconds || 3600, permissions || ['stt', 'tts']);
    
    console.log(`🔑 Issued ephemeral keys for device: ${device_id}`);
    
    return {
      statusCode: 200,
      body: {
        status: 'success',
        keys: {
          stt: keys.sttKey,
          tts: keys.ttsKey
        },
        providers: {
          stt: keys.sttProvider,
          tts: keys.ttsProvider
        },
        endpoints: {
          stt: tunnelConfig ? `${tunnelConfig.publicUrl}/proxy/stt/transcribe` : keys.sttEndpoint,
          tts: tunnelConfig ? `${tunnelConfig.publicUrl}/proxy/tts/synthesize` : keys.ttsEndpoint
        },
        config: {
          stt: {
            baseUrl: keys.sttBaseUrl,
            model: keys.sttModel
          },
          tts: {
            baseUrl: keys.ttsBaseUrl,
            model: keys.ttsModel,
            voice: keys.ttsVoice
          }
        },
        expires_at: keys.expiresAt,
        expires_in: keys.expiresIn,
        permissions: keys.permissions
      }
    };
  }
  
  if (path === '/keys/refresh' && method === 'POST') {
    const bodyObj = body as { device_id?: string };
    const { device_id } = bodyObj;
    if (!device_id) {
      return { statusCode: 400, body: { error: 'device_id is required' } };
    }
    const keys = keyManager.refreshKeys(device_id);
    
    if (keys) {
      console.log(`🔄 Refreshed keys for device: ${device_id}`);
      return {
        statusCode: 200,
        body: {
          status: 'refreshed',
          expires_at: keys.expiresAt,
          expires_in: keys.expiresIn
        }
      };
    }
    
    return { statusCode: 404, body: { error: 'Keys not found' } };
  }
  
  if (path === '/keys/revoke' && method === 'DELETE') {
    const device_id = query.device_id;
    if (!device_id) {
      return { statusCode: 400, body: { error: 'device_id is required' } };
    }
    keyManager.revokeKeys(device_id);
    
    console.log(`🔒 Revoked keys for device: ${device_id}`);
    
    return { statusCode: 200, body: { status: 'revoked' } };
  }
  
  return { statusCode: 404, body: { error: 'Not found' } };
}

// Tunnel status endpoint - returns connection status
function handleTunnelStatusRequest(): TunnelResponse {
  // Check if tunnel WebSocket connection is active
  // This is a simple health check - if we can respond, we're connected
  return {
    statusCode: 200,
    body: {
      connected: true,
      status: 'connected',
      timestamp: Date.now()
    }
  };
}

// Terminal management endpoints
async function handleTerminalRequest(method: string, path: string, body: unknown, _query: Record<string, string | undefined>, _headers: Record<string, string | string[] | undefined>): Promise<TunnelResponse> {
  if (path === '/terminal/list' && method === 'GET') {
    const sessions = terminalManager.listSessions();
    return {
      statusCode: 200,
      body: {
        sessions: sessions.map(s => ({
          session_id: s.sessionId,
          working_dir: s.workingDir,
          terminal_type: s.terminalType,
          name: s.name
        }))
      }
    };
  }
  
  if (path === '/terminal/create' && method === 'POST') {
    const bodyObj = body as { terminal_type?: string; working_dir?: string; name?: string };
    const { terminal_type, working_dir, name } = bodyObj;
    
    if (!isAllowedTerminalType(terminal_type)) {
      return { statusCode: 400, body: { error: `terminal_type must be one of: ${ALLOWED_TERMINAL_TYPES.join(', ')}` } };
    }
    
    const session = await terminalManager.createSession(terminal_type, working_dir, name);
    
    console.log(`📟 Created terminal session: ${session.sessionId} (${terminal_type})`);
    
    return {
      statusCode: 200,
      body: {
        session_id: session.sessionId,
        working_dir: session.workingDir,
        terminal_type: session.terminalType,
        name: session.name,
        status: 'created'
      }
    };
  }
  
  const renameMatch = path.match(/^\/terminal\/([^\/]+)\/rename$/);
  if (renameMatch && method === 'POST') {
    const sessionId = renameMatch[1];
    const bodyObj = body as { name?: string };
    const { name } = bodyObj;
    
    if (!name || typeof name !== 'string') {
      return { statusCode: 400, body: { error: 'name is required and must be a string' } };
    }
    
    try {
      terminalManager.renameSession(sessionId, name);
      console.log(`✏️  Renamed session ${sessionId} to: ${name}`);
      return {
        statusCode: 200,
        body: {
          session_id: sessionId,
          name,
          status: 'renamed'
        }
      };
    } catch (error) {
      if (error instanceof Error && error.message === 'Session not found') {
        return { statusCode: 404, body: { error: 'Session not found' } };
      }
      return { statusCode: 500, body: { error: 'Failed to rename session' } };
    }
  }
  
  const historyMatch = path.match(/^\/terminal\/([^\/]+)\/history$/);
  if (historyMatch && method === 'GET') {
    const sessionId = historyMatch[1];
    const history = terminalManager.getHistory(sessionId);
    
    console.log(`📜 Retrieved history for ${sessionId} (${history.length} chars)`);
    
    return {
      statusCode: 200,
      body: {
        session_id: sessionId,
        history
      }
    };
  }
  
  const executeMatch = path.match(/^\/terminal\/([^\/]+)\/execute$/);
  if (executeMatch && method === 'POST') {
    const sessionId = executeMatch[1];
    const bodyObj = body as { command?: string };
    const { command } = bodyObj;
    
    console.log(`🌉 [Tunnel] POST /terminal/${sessionId}/execute - Command: ${JSON.stringify(command)}`);
    console.log(`⚡ Command bytes: ${Array.from(command || '').map(c => c.charCodeAt(0)).join(', ')}`);
    
    const output = await terminalManager.executeCommand(sessionId, command || '');
    
    console.log(`✅ [Tunnel] Command executed in ${sessionId}, output length: ${output.length}`);
    
    return {
      statusCode: 200,
      body: {
        session_id: sessionId,
        command,
        output
      }
    };
  }
  
  const resizeMatch = path.match(/^\/terminal\/([^\/]+)\/resize$/);
  if (resizeMatch && method === 'POST') {
    const sessionId = resizeMatch[1];
    const bodyObj = body as { cols?: number; rows?: number };
    const { cols, rows } = bodyObj;
    
    if (!cols || !rows) {
      return { statusCode: 400, body: { error: 'cols and rows are required' } };
    }
    
    terminalManager.resizeTerminal(sessionId, cols, rows);
    
    console.log(`📐 Resized ${sessionId}: ${cols}x${rows}`);
    
    return {
      statusCode: 200,
      body: {
        session_id: sessionId,
        cols,
        rows,
        status: 'resized'
      }
    };
  }
  
  const deleteMatch = path.match(/^\/terminal\/([^\/]+)$/);
  if (deleteMatch && method === 'DELETE') {
    const sessionId = deleteMatch[1];
    
    await terminalManager.destroySession(sessionId);
    
    console.log(`🗑️  Deleted session: ${sessionId}`);
    
    return {
      statusCode: 200,
      body: {
        session_id: sessionId,
        status: 'deleted'
      }
    };
  }
  
  return { statusCode: 404, body: { error: 'Not found' } };
}

// AI Agent endpoints
async function handleAgentRequest(method: string, path: string, body: unknown, _headers: Record<string, string | string[] | undefined>): Promise<TunnelResponse> {
  if (path === '/agent/execute' && method === 'POST') {
    const bodyObj = body as { command?: string; session_id?: string };
    const { command, session_id } = bodyObj;
    
    if (!command) {
      return { statusCode: 400, body: { error: 'command is required' } };
    }
    
    console.log(`🤖 AI Agent executing: ${command}${session_id ? ` (session: ${session_id})` : ' (no session - agent mode)'}`);
    
    // session_id is optional - agent can work without terminal context for workspace/worktree operations
    const result = await aiAgent.execute(command, session_id, terminalManager);
    
    return {
      statusCode: 200,
      body: {
        type: 'ai_response',
        session_id: result.sessionId || session_id || null,
        command,
        result: result.output,
        via: 'ai_agent'
      }
    };
  }
  
  return { statusCode: 404, body: { error: 'Not found' } };
}

// STT Proxy endpoints
async function handleSTTProxyRequest(method: string, path: string, body: unknown, _headers: Record<string, string | string[] | undefined>): Promise<TunnelResponse> {
  if (path === '/proxy/stt/transcribe' && method === 'POST') {
    try {
      // Body should be JSON with base64-encoded audio
      const bodyObj = body as { audio?: string; language?: string };
      const { audio, language } = bodyObj;

      if (!audio) {
        return { statusCode: 400, body: { error: 'audio data is required (base64 encoded)' } };
      }

      const audioData = Buffer.from(audio, 'base64');

      console.log(`🎤 STT Proxy: Received transcription request`);
      console.log(`   Audio size: ${audioData.length} bytes`);
      console.log(`   Language: ${language || 'auto'}`);

      const transcription = await transcribeAudio(sttProvider, audioData, language);

      return {
        statusCode: 200,
        body: {
          text: transcription
        }
      };
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      console.error(`❌ STT Proxy error: ${errorMessage}`);
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  return { statusCode: 404, body: { error: 'Not found' } };
}

// TTS Proxy endpoints
async function handleTTSProxyRequest(method: string, path: string, body: unknown, _headers: Record<string, string | string[] | undefined>): Promise<TunnelResponse> {
  if (path === '/proxy/tts/synthesize' && method === 'POST') {
    try {
      const bodyObj = body as { text?: string; voice?: string; speed?: number; language?: string };
      const { text, voice, speed, language } = bodyObj;

      if (!text) {
        return { statusCode: 400, body: { error: 'text is required' } };
      }

      // Get default voice from provider if not specified
      const defaultVoice = ttsProvider.getVoice();
      const finalVoice = voice || defaultVoice;

      // Use speed from client if provided, otherwise default to 1.0
      const finalSpeed = speed ?? 1.0;

      console.log(`🔊 TTS Proxy: Received synthesis request`);
      console.log(`   Text length: ${text.length} characters`);
      console.log(`   Voice: ${finalVoice} (client: ${voice || 'not specified'}, default: ${defaultVoice})`);
      console.log(`   Speed: ${finalSpeed} (client: ${speed || 'not specified'})`);
      if (language) {
        console.log(`   Language preference: ${language}`);
      }

      // Use voice and speed from client, but model and other params from server config
      const audioBuffer = await synthesizeSpeech(ttsProvider, text, finalVoice, finalSpeed);

      // Return audio as base64 for easy transmission
      return {
        statusCode: 200,
        body: {
          audio: audioBuffer.toString('base64'),
          format: 'audio/mpeg' // Adjust based on provider
        }
      };
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      console.error(`❌ TTS Proxy error: ${errorMessage}`);
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  return { statusCode: 404, body: { error: 'Not found' } };
}

// Workspace and Worktree management endpoints
async function handleWorkspaceRequest(method: string, path: string, body: unknown, _query: Record<string, string | undefined>, _headers: Record<string, string | string[] | undefined>): Promise<TunnelResponse> {
  // Workspace management
  if (path === '/workspace/list' && method === 'GET') {
    try {
      const workspaces = await workspaceManager.listWorkspaces();
      return {
        statusCode: 200,
        body: {
          workspaces: workspaces.map(w => ({
            name: w.name,
            path: w.path,
            created_at: w.createdAt
          }))
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  if (path === '/workspace/create' && method === 'POST') {
    try {
      const bodyObj = body as { workspace_name?: string };
      const { workspace_name } = bodyObj;
      if (!workspace_name) {
        return { statusCode: 400, body: { error: 'workspace_name is required' } };
      }
      const workspace = await workspaceManager.createWorkspace(workspace_name);
      return {
        statusCode: 200,
        body: {
          name: workspace.name,
          path: workspace.path,
          created_at: workspace.createdAt,
          status: 'created'
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  const workspaceMatch = path.match(/^\/workspace\/([^\/]+)$/);
  if (workspaceMatch && method === 'DELETE') {
    try {
      const workspace = workspaceMatch[1];
      await workspaceManager.removeWorkspace(workspace);
      return {
        statusCode: 200,
        body: {
          workspace,
          status: 'deleted'
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  // Repository management
  const cloneMatch = path.match(/^\/workspace\/([^\/]+)\/clone$/);
  if (cloneMatch && method === 'POST') {
    try {
      const workspace = cloneMatch[1];
      const bodyObj = body as { repo_url?: string; repo_name?: string };
      const { repo_url, repo_name } = bodyObj;
      if (!repo_url) {
        return { statusCode: 400, body: { error: 'repo_url is required' } };
      }
      const repo = await workspaceManager.cloneRepository(workspace, repo_url, repo_name);
      return {
        statusCode: 200,
        body: {
          name: repo.name,
          path: repo.path,
          remote_url: repo.remoteUrl,
          cloned_at: repo.clonedAt,
          status: 'cloned'
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  const reposMatch = path.match(/^\/workspace\/([^\/]+)\/repos$/);
  if (reposMatch && method === 'GET') {
    try {
      const workspace = reposMatch[1];
      const repos = await workspaceManager.listRepositories(workspace);
      return {
        statusCode: 200,
        body: {
          workspace,
          repositories: repos.map(r => ({
            name: r.name,
            path: r.path,
            remote_url: r.remoteUrl,
            cloned_at: r.clonedAt
          }))
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  // Worktree management
  const worktreeCreateMatch = path.match(/^\/workspace\/([^\/]+)\/([^\/]+)\/worktree\/create$/);
  if (worktreeCreateMatch && method === 'POST') {
    try {
      const workspace = worktreeCreateMatch[1];
      const repo = worktreeCreateMatch[2];
      const bodyObj = body as { branch_or_feature?: string; worktree_name?: string };
      const { branch_or_feature, worktree_name } = bodyObj;
      if (!branch_or_feature) {
        return { statusCode: 400, body: { error: 'branch_or_feature is required' } };
      }
      const worktree = await worktreeManager.createWorktree(workspace, repo, branch_or_feature, worktree_name);
      return {
        statusCode: 200,
        body: {
          name: worktree.name,
          path: worktree.path,
          branch: worktree.branch,
          created_at: worktree.createdAt,
          status: 'created'
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  const worktreesMatch = path.match(/^\/workspace\/([^\/]+)\/([^\/]+)\/worktrees$/);
  if (worktreesMatch && method === 'GET') {
    try {
      const workspace = worktreesMatch[1];
      const repo = worktreesMatch[2];
      const worktrees = await worktreeManager.listWorktrees(workspace, repo);
      return {
        statusCode: 200,
        body: {
          workspace,
          repo,
          worktrees: worktrees.map(w => ({
            name: w.name,
            path: w.path,
            branch: w.branch,
            created_at: w.createdAt
          }))
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  const worktreeDeleteMatch = path.match(/^\/workspace\/([^\/]+)\/([^\/]+)\/worktree\/([^\/]+)$/);
  if (worktreeDeleteMatch && method === 'DELETE') {
    try {
      const workspace = worktreeDeleteMatch[1];
      const repo = worktreeDeleteMatch[2];
      const worktreeName = worktreeDeleteMatch[3];
      await worktreeManager.removeWorktree(workspace, repo, worktreeName);
      return {
        statusCode: 200,
        body: {
          workspace,
          repo,
          worktree: worktreeName,
          status: 'deleted'
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  const worktreePathMatch = path.match(/^\/workspace\/([^\/]+)\/([^\/]+)\/worktree\/([^\/]+)\/path$/);
  if (worktreePathMatch && method === 'GET') {
    try {
      const workspace = worktreePathMatch[1];
      const repo = worktreePathMatch[2];
      const worktreeName = worktreePathMatch[3];
      const worktreePath = worktreeManager.getWorktreePath(workspace, repo, worktreeName);
      return {
        statusCode: 200,
        body: {
          workspace,
          repo,
          worktree: worktreeName,
          path: worktreePath
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  return { statusCode: 404, body: { error: 'Not found' } };
}

// Start the application
console.log('🎯 Laptop application starting...');
console.log('📋 Loading configuration from environment variables...');

// Show current configuration
if (process.env.TUNNEL_SERVER_URL) {
  console.log(`   Tunnel Server: ${process.env.TUNNEL_SERVER_URL}`);
} else {
  console.log('   ⚠️  TUNNEL_SERVER_URL not set');
}

if (process.env.OPENAI_API_KEY) {
  console.log(`   OpenAI API Key: ${process.env.OPENAI_API_KEY.substring(0, 8)}...`);
} else {
  console.log('   ⚠️  OPENAI_API_KEY not set');
}

if (process.env.LAPTOP_NAME) {
  console.log(`   Laptop Name: ${process.env.LAPTOP_NAME}`);
}

console.log('');

// Start localhost web server
server.listen(WEB_PORT, '127.0.0.1', () => {
  console.log('');
  console.log('═══════════════════════════════════════════════════════════');
  console.log(`🌐 Web Interface: http://localhost:${WEB_PORT}`);
  console.log('   (Only accessible from localhost)');
  console.log('═══════════════════════════════════════════════════════════');
  console.log('');
});

// Initialize workspace manager
workspaceManager.initialize().then(() => {
  console.log('✅ Workspace manager initialized');
}).catch((error) => {
  console.error('❌ Failed to initialize workspace manager:', error);
});

initializeTunnel().then(() => {
  console.log('✅ Laptop application ready!');
  console.log('📱 Waiting for mobile device connection...');
  console.log('💡 The application will continue running and retry if tunnel server disconnects');
});

// Graceful shutdown handler
let isShuttingDown = false;

async function gracefulShutdown(signal: string): Promise<void> {
  if (isShuttingDown) {
    console.log('⚠️  Shutdown already in progress, forcing exit...');
    process.exit(1);
    return;
  }
  
  isShuttingDown = true;
  console.log(`\n🛑 Received ${signal}, shutting down gracefully...`);
  
  try {
    // Stop accepting new connections
    server.close(() => {
      console.log('✅ HTTP server closed');
    });
    
    // Cleanup terminal sessions (with timeout)
    const cleanupPromise = terminalManager.cleanup();
    const timeoutPromise = new Promise<void>((resolve) => {
      setTimeout(() => {
        console.log('⚠️  Cleanup timeout reached, forcing exit...');
        resolve();
      }, 5000); // 5 second timeout
    });
    
    await Promise.race([cleanupPromise, timeoutPromise]);
    console.log('✅ Terminal sessions cleaned up');
    
    // Disconnect tunnel client
    if (tunnelClient) {
      tunnelClient.disconnect();
      console.log('✅ Tunnel client disconnected');
    }
    
    console.log('✅ Shutdown complete');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error during shutdown:', error);
    process.exit(1);
  }
}

// Register signal handlers
process.on('SIGINT', () => {
  gracefulShutdown('SIGINT').catch((error) => {
    console.error('❌ Shutdown error:', error);
    process.exit(1);
  });
});

process.on('SIGTERM', () => {
  gracefulShutdown('SIGTERM').catch((error) => {
    console.error('❌ Shutdown error:', error);
    process.exit(1);
  });
});
