import { WebSocket } from 'ws';

export interface TunnelConfig {
  tunnelId: string;
  apiKey: string;
  publicUrl: string;
  wsUrl: string;
}

interface TunnelRequest {
  method: string;
  path: string;
  body: unknown;
  query: Record<string, string | undefined>;
  headers: Record<string, string | string[] | undefined>;
  requestId: string;
}

interface TunnelResponse {
  statusCode: number;
  body: unknown;
}

export enum ConnectionState {
  Connecting = 'connecting',
  Connected = 'connected',
  Disconnected = 'disconnected',
  Reconnecting = 'reconnecting',
  Dead = 'dead'
}

export class TunnelClient {
  private ws: WebSocket | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = Infinity; // Keep trying forever
  private terminalInputHandler: ((sessionId: string, data: string) => void) | null = null;
  private lastPongReceived: number = 0;
  private pingInterval: NodeJS.Timeout | null = null;
  private healthCheckInterval: NodeJS.Timeout | null = null;
  private connectionState: ConnectionState = ConnectionState.Disconnected;
  private stateChangeCallback: ((state: ConnectionState) => void) | null = null;
  
  // Heartbeat configuration
  private readonly PING_INTERVAL_MS = 20000; // 20 seconds
  private readonly PONG_TIMEOUT_MS = 30000; // 30 seconds
  
  constructor(
    private config: TunnelConfig,
    private requestHandler: (req: TunnelRequest) => Promise<TunnelResponse>,
    private clientAuthKey?: string
  ) {}
  
  setTerminalInputHandler(handler: (sessionId: string, data: string) => void): void {
    this.terminalInputHandler = handler;
  }
  
  setStateChangeCallback(callback: (state: ConnectionState) => void): void {
    this.stateChangeCallback = callback;
  }
  
  getConnectionState(): ConnectionState {
    return this.connectionState;
  }
  
  private setConnectionState(state: ConnectionState): void {
    if (this.connectionState !== state) {
      this.connectionState = state;
      if (this.stateChangeCallback) {
        this.stateChangeCallback(state);
      }
    }
  }
  
  sendTerminalOutput(sessionId: string, data: string): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({
        type: 'terminal_output',
        sessionId,
        data
      }));
    }
  }

  sendRecordingOutput(
    sessionId: string,
    payload: { text: string; delta: string; raw?: string; timestamp: number; isComplete?: boolean }
  ): void {
    if (!this.ws) {
      console.error(`❌❌❌ TunnelClient: WebSocket is null, cannot send recording_output`);
      return;
    }
    
    if (this.ws.readyState !== WebSocket.OPEN) {
      console.warn(`⚠️⚠️⚠️ TunnelClient: Cannot send recording_output - WebSocket not OPEN, state=${this.ws.readyState} (1=OPEN, 0=CONNECTING, 2=CLOSING, 3=CLOSED)`);
      return;
    }
    
    const message = {
      type: 'recording_output',
      sessionId,
      ...payload
    };
    const messageStr = JSON.stringify(message);
    console.log(`📤📤📤 TunnelClient: Sending recording_output to tunnel: sessionId=${sessionId}, text=${payload.text.length} chars, isComplete=${payload.isComplete ?? 'undefined'}, wsState=${this.ws.readyState}`);
    console.log(`📤📤📤 TunnelClient: Full message: ${messageStr.substring(0, 300)}`);
    
    try {
      this.ws.send(messageStr, (error) => {
        if (error) {
          console.error(`❌❌❌ TunnelClient: Error sending recording_output: ${error.message}`);
        } else {
          console.log(`✅✅✅ TunnelClient: Successfully sent recording_output message (${messageStr.length} bytes)`);
        }
      });
    } catch (error) {
      console.error(`❌❌❌ TunnelClient: Exception while sending recording_output: ${error}`);
    }
  }
  
  async connect(): Promise<void> {
    const wsUrl = `${this.config.wsUrl}?api_key=${this.config.apiKey}`;
    
    console.log(`📡 Connecting to tunnel: ${wsUrl}`);
    
    this.ws = new WebSocket(wsUrl);
    this.setConnectionState(ConnectionState.Connecting);
    
    this.ws.on('open', () => {
      console.log('✅ Tunnel connected');
      this.reconnectAttempts = 0;
      this.lastPongReceived = Date.now();
      this.setConnectionState(ConnectionState.Connected);
      
      if (this.clientAuthKey) {
        this.ws?.send(JSON.stringify({
          type: 'client_auth_key',
          key: this.clientAuthKey
        }));
      }
      
      // Setup heartbeat
      this.setupHeartbeat();
    });
    
    this.ws.on('pong', () => {
      this.lastPongReceived = Date.now();
      if (this.connectionState === ConnectionState.Dead) {
        this.setConnectionState(ConnectionState.Connected);
      }
    });
    
    this.ws.on('message', async (data) => {
      try {
        const message = JSON.parse(data.toString());
        
        // Update last pong on any message (indicates connection is alive)
        this.lastPongReceived = Date.now();
        
        if (message.type === 'http_request') {
          // Normalize path - remove any double slashes and ensure it starts with /
          let normalizedPath = message.path || '/';
          if (!normalizedPath.startsWith('/')) {
            normalizedPath = '/' + normalizedPath;
          }
          // Remove double slashes (except at the start)
          normalizedPath = normalizedPath.replace(/\/+/g, '/');
          
          console.log(`📥 Tunnel: ${message.method} ${message.path} -> normalized: ${normalizedPath}`);
          
          const response = await this.requestHandler({
            ...message,
            path: normalizedPath
          });
          
          // Send response back through tunnel
          this.ws?.send(JSON.stringify({
            type: 'http_response',
            requestId: message.requestId,
            statusCode: response.statusCode || 200,
            body: response.body
          }));
        } else if (message.type === 'terminal_input') {
          // Handle terminal input from iPhone
          if (this.terminalInputHandler) {
            this.terminalInputHandler(message.sessionId, message.data);
          }
        }
      } catch (error) {
        console.error('❌ Error processing tunnel message:', error);
      }
    });
    
    this.ws.on('close', () => {
      console.log('📡 Tunnel disconnected');
      this.cleanupHeartbeat();
      this.setConnectionState(ConnectionState.Disconnected);
      this.attemptReconnect();
    });
    
    this.ws.on('error', (error) => {
      console.error('❌ Tunnel error:', error);
      this.cleanupHeartbeat();
      this.setConnectionState(ConnectionState.Disconnected);
    });
  }
  
  private setupHeartbeat(): void {
    this.cleanupHeartbeat();
    
    // Send periodic pings
    this.pingInterval = setInterval(() => {
      if (this.ws?.readyState === WebSocket.OPEN) {
        this.ws.ping();
      }
    }, this.PING_INTERVAL_MS);
    
    // Check for dead connections
    this.healthCheckInterval = setInterval(() => {
      const timeSinceLastPong = Date.now() - this.lastPongReceived;
      if (timeSinceLastPong > this.PONG_TIMEOUT_MS) {
        console.log(`⚠️ Tunnel appears dead (no pong for ${timeSinceLastPong}ms)`);
        this.setConnectionState(ConnectionState.Dead);
        this.cleanupHeartbeat();
        if (this.ws) {
          this.ws.terminate();
        }
        this.attemptReconnect();
      }
    }, this.PONG_TIMEOUT_MS);
  }
  
  private cleanupHeartbeat(): void {
    if (this.pingInterval) {
      clearInterval(this.pingInterval);
      this.pingInterval = null;
    }
    if (this.healthCheckInterval) {
      clearInterval(this.healthCheckInterval);
      this.healthCheckInterval = null;
    }
  }
  
  private attemptReconnect(): void {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error('❌ Max reconnection attempts reached');
      console.log('💡 Please restart the application or check tunnel server');
      this.setConnectionState(ConnectionState.Disconnected);
      return;
    }
    
    this.reconnectAttempts++;
    const delay = Math.min(Math.pow(2, this.reconnectAttempts) * 1000, 30000); // Max 30s
    
    console.log(`🔄 Reconnecting to tunnel in ${delay / 1000}s (attempt ${this.reconnectAttempts}${this.maxReconnectAttempts === Infinity ? '' : '/' + this.maxReconnectAttempts})`);
    this.setConnectionState(ConnectionState.Reconnecting);
    
    setTimeout(() => {
      console.log('🔌 Attempting to reconnect...');
      this.connect().catch(err => {
        console.error('❌ Reconnection failed:', err.message);
        this.setConnectionState(ConnectionState.Disconnected);
      });
    }, delay);
  }
  
  disconnect(): void {
    this.cleanupHeartbeat();
    this.setConnectionState(ConnectionState.Disconnected);
    this.ws?.close();
  }
}
