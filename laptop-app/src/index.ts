import express from 'express';
import { WebSocket } from 'ws';
import dotenv from 'dotenv';
import QRCode from 'qrcode';
import { TerminalManager } from './terminal/TerminalManager.js';
import { KeyManager } from './keys/KeyManager.js';
import { TunnelClient } from './tunnel/TunnelClient.js';
import { AIAgent } from './agent/AIAgent.js';

dotenv.config();

const app = express();
app.use(express.json());

// Initialize components
const terminalManager = new TerminalManager();
const keyManager = new KeyManager(process.env.OPENAI_API_KEY!, process.env.ELEVENLABS_API_KEY);
const aiAgent = new AIAgent(process.env.OPENAI_API_KEY!);

let tunnelClient: TunnelClient | null = null;
let tunnelConfig: any = null;

console.log('🚀 Laptop Application starting...');

// Initialize tunnel connection
async function initializeTunnel() {
  try {
    const response = await fetch(`${process.env.TUNNEL_SERVER_URL}/tunnel/create`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: process.env.LAPTOP_NAME || 'My Laptop' })
    });
    
    const data = await response.json();
    tunnelConfig = data.config;
    
    console.log('✅ Tunnel created:');
    console.log(`   Tunnel ID: ${tunnelConfig.tunnelId}`);
    console.log(`   Public URL: ${tunnelConfig.publicUrl}`);
    
    // Generate and display QR code
    const qrData = JSON.stringify({
      tunnelId: tunnelConfig.tunnelId,
      tunnelUrl: tunnelConfig.publicUrl.replace('/api/' + tunnelConfig.tunnelId, ''),
      wsUrl: tunnelConfig.wsUrl.replace('/tunnel/' + tunnelConfig.tunnelId, ''),
      keyEndpoint: `${tunnelConfig.publicUrl}/keys/request`
    });
    
    const qrCodeText = await QRCode.toString(qrData, { type: 'terminal', small: true });
    console.log('\n📱 Scan this QR code with your iPhone:\n');
    console.log(qrCodeText);
    console.log('\n');
    
    // Connect to tunnel
    tunnelClient = new TunnelClient(tunnelConfig, handleTunnelRequest);
    await tunnelClient.connect();
    
  } catch (error) {
    console.error('❌ Failed to initialize tunnel:', error);
    process.exit(1);
  }
}

// Handle incoming HTTP requests from tunnel
async function handleTunnelRequest(req: any): Promise<any> {
  const { method, path, body, query, headers } = req;
  
  console.log(`📥 ${method} ${path}`);
  
  try {
    // Route to appropriate handler
    if (path.startsWith('/keys/')) {
      return handleKeyRequest(method, path, body, headers);
    } else if (path.startsWith('/terminal/')) {
      return handleTerminalRequest(method, path, body, query, headers);
    } else if (path.startsWith('/agent/')) {
      return handleAgentRequest(method, path, body, headers);
    } else {
      return { statusCode: 404, body: { error: 'Not found' } };
    }
  } catch (error: any) {
    console.error('❌ Request error:', error);
    return { statusCode: 500, body: { error: error.message } };
  }
}

// Key management endpoints
function handleKeyRequest(method: string, path: string, body: any, headers: any): any {
  if (path === '/keys/request' && method === 'POST') {
    const { device_id, tunnel_id, duration_seconds, permissions } = body;
    const keys = keyManager.issueEphemeralKeys(device_id, duration_seconds || 3600, permissions || ['stt', 'tts']);
    
    console.log(`🔑 Issued ephemeral keys for device: ${device_id}`);
    
    return {
      statusCode: 200,
      body: {
        status: 'success',
        keys: {
          openai: keys.openaiKey,
          elevenlabs: keys.elevenLabsKey
        },
        expires_at: keys.expiresAt,
        expires_in: keys.expiresIn,
        permissions: keys.permissions
      }
    };
  }
  
  if (path === '/keys/refresh' && method === 'POST') {
    const { device_id } = body;
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
    keyManager.revokeKeys(device_id);
    
    console.log(`🔒 Revoked keys for device: ${device_id}`);
    
    return { statusCode: 200, body: { status: 'revoked' } };
  }
  
  return { statusCode: 404, body: { error: 'Not found' } };
}

// Terminal management endpoints
function handleTerminalRequest(method: string, path: string, body: any, query: any, headers: any): any {
  if (path === '/terminal/list' && method === 'GET') {
    const sessions = terminalManager.listSessions();
    return {
      statusCode: 200,
      body: {
        sessions: sessions.map(s => ({
          session_id: s.sessionId,
          working_dir: s.workingDir
        }))
      }
    };
  }
  
  if (path === '/terminal/create' && method === 'POST') {
    const { working_dir } = body;
    const session = terminalManager.createSession(working_dir);
    
    console.log(`📟 Created terminal session: ${session.sessionId}`);
    
    return {
      statusCode: 200,
      body: {
        session_id: session.sessionId,
        working_dir: session.workingDir,
        status: 'created'
      }
    };
  }
  
  const executeMatch = path.match(/^\/terminal\/([^\/]+)\/execute$/);
  if (executeMatch && method === 'POST') {
    const sessionId = executeMatch[1];
    const { command } = body;
    
    const output = terminalManager.executeCommand(sessionId, command);
    
    console.log(`⚡ Executed in ${sessionId}: ${command}`);
    
    return {
      statusCode: 200,
      body: {
        session_id: sessionId,
        command,
        output
      }
    };
  }
  
  return { statusCode: 404, body: { error: 'Not found' } };
}

// AI Agent endpoints
async function handleAgentRequest(method: string, path: string, body: any, headers: any): Promise<any> {
  if (path === '/agent/execute' && method === 'POST') {
    const { command, session_id } = body;
    
    console.log(`🤖 AI Agent executing: ${command}`);
    
    const result = await aiAgent.execute(command, session_id, terminalManager);
    
    return {
      statusCode: 200,
      body: {
        type: 'ai_response',
        session_id,
        command,
        result,
        via: 'ai_agent'
      }
    };
  }
  
  return { statusCode: 404, body: { error: 'Not found' } };
}

// Start the application
initializeTunnel().then(() => {
  console.log('✅ Laptop application ready!');
  console.log('📱 Waiting for mobile device connection...');
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n🛑 Shutting down...');
  terminalManager.cleanup();
  tunnelClient?.disconnect();
  process.exit(0);
});
