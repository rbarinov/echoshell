import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import QRCode from 'qrcode';
import { TerminalManager } from './terminal/TerminalManager';
import { KeyManager } from './keys/KeyManager';
import { TunnelClient, type TunnelConfig } from './tunnel/TunnelClient';
import { AIAgent } from './agent/AIAgent';
import { StateManager } from './storage/StateManager';
import { RecordingStreamManager } from './output/RecordingStreamManager';
import { OutputRouter } from './output/OutputRouter';
import { createLLMProvider } from './agent/LLMProvider';
import { createSTTProvider } from './keys/STTProvider';
import { createTTSProvider } from './keys/TTSProvider';
import { WorkspaceManager } from './workspace/WorkspaceManager';
import { WorktreeManager } from './workspace/WorktreeManager';
import { createAppServer, startServer, localhostOnly } from './server';
import { createTerminalRoutes } from './routes/terminal';
import { createWorkspaceRoutes } from './routes/workspace';
import { setupTerminalWebSocket } from './websocket/terminalWebSocket';
import { TerminalHandler } from './handlers/terminalHandler';
import { KeyHandler } from './handlers/keyHandler';
import { WorkspaceHandler } from './handlers/workspaceHandler';
import { AgentHandler } from './handlers/agentHandler';
import { ProxyHandler } from './handlers/proxyHandler';
import type { TunnelRequest, TunnelResponse } from './types';
import logger from './utils/logger';

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

// Create HTTP server with WebSocket support
const WEB_PORT = parseInt(process.env.WEB_INTERFACE_PORT || '8002', 10);
const publicDir = path.resolve(__dirname, '../public');

const { app, server, wss } = createAppServer({
  port: WEB_PORT,
  publicDir
});

// Apply localhost restriction to all routes
app.use(localhostOnly);

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

// Initialize OutputRouter (tunnel client will be set later)
const outputRouter = new OutputRouter(terminalManager, null);

// Set OutputRouter in TerminalManager
terminalManager.setOutputRouter(outputRouter);

// Initialize handlers for tunnel requests
let terminalHandler: TerminalHandler;
let keyHandler: KeyHandler;
let workspaceHandler: WorkspaceHandler;
let agentHandler: AgentHandler;
let proxyHandler: ProxyHandler;

terminalHandler = new TerminalHandler(terminalManager);
keyHandler = new KeyHandler(keyManager, null); // tunnelConfig will be set later
workspaceHandler = new WorkspaceHandler(workspaceManager, worktreeManager);
agentHandler = new AgentHandler(aiAgent, terminalManager);
proxyHandler = new ProxyHandler(sttProvider, ttsProvider);

// Setup routes
app.use('/terminal', createTerminalRoutes(terminalManager));
app.use('/workspace', createWorkspaceRoutes(workspaceManager, worktreeManager));

// Setup WebSocket
setupTerminalWebSocket(wss, terminalManager, outputRouter);

let tunnelClient: TunnelClient | null = null;
let tunnelConfig: TunnelConfig | null = null;
let reconnectAttempt = 0;
const maxReconnectAttempts = 10;

// Recording stream manager - will be initialized after tunnel client is available
let recordingStreamManager: RecordingStreamManager | null = null;

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
    
    // Update OutputRouter with tunnel client
    outputRouter.setTunnelClient(tunnelClient);
    
    // Update KeyHandler with tunnel config
    keyHandler.setTunnelConfig(tunnelConfig);
    
    // Initialize RecordingStreamManager now that tunnel client is available
    recordingStreamManager = new RecordingStreamManager(
      terminalManager,
      () => tunnelClient,
      outputRouter
    );
    
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
  const { method, path, headers } = req;
  
  logger.debug('Tunnel request', { method, path });
  
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
      return keyHandler.handleRequest(req);
    } else if (path.startsWith('/terminal/')) {
      return await terminalHandler.handleRequest(req);
    } else if (path.startsWith('/agent/')) {
      return await agentHandler.handleRequest(req);
    } else if (path.startsWith('/proxy/')) {
      return await proxyHandler.handleRequest(req);
    } else if (path.startsWith('/workspace/')) {
      return await workspaceHandler.handleRequest(req);
    } else if (path === '/tunnel-status' && method === 'GET') {
      return {
        statusCode: 200,
        body: {
          connected: true,
          status: 'connected',
          timestamp: Date.now()
        }
      };
    } else {
      return { statusCode: 404, body: { error: 'Not found' } };
    }
  } catch (error: unknown) {
    logger.error('Request error', error instanceof Error ? error : new Error(String(error)));
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    return { statusCode: 500, body: { error: errorMessage } };
  }
}

// Start the application
logger.info('Laptop application starting');
logger.info('Loading configuration from environment variables', {
  hasTunnelServerUrl: !!process.env.TUNNEL_SERVER_URL,
  hasOpenAIApiKey: !!process.env.OPENAI_API_KEY,
  laptopName: process.env.LAPTOP_NAME || null
});

if (!process.env.TUNNEL_SERVER_URL) {
  logger.warn('TUNNEL_SERVER_URL not set');
}
if (!process.env.OPENAI_API_KEY) {
  logger.warn('OPENAI_API_KEY not set');
}

// Start localhost web server
startServer(server, WEB_PORT).then(() => {
  logger.info('Web interface started', { port: WEB_PORT, url: `http://localhost:${WEB_PORT}` });
});

// Initialize workspace manager
workspaceManager.initialize().then(() => {
  logger.info('Workspace manager initialized');
}).catch((error) => {
  logger.error('Failed to initialize workspace manager', error instanceof Error ? error : new Error(String(error)));
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
