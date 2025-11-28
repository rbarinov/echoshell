import { WebSocket } from 'ws';
import { AgentEvent } from '../types/AgentEvent.js';
import { AgentWebSocketHandler } from './AgentWebSocketHandler.js';

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

// Legacy interfaces (DEPRECATED - will be removed)
export interface AgentRequest {
  tunnelId: string;
  streamKey: string;
  payload: {
    type: 'execute' | 'execute_audio' | 'reset_context';
    command?: string;
    audio?: string;
    audio_format?: string;
    language?: string;
    tts_enabled?: boolean;
    tts_speed?: number;
  };
}

export interface AgentResponsePayload {
  type: 'transcription' | 'chunk' | 'complete' | 'error' | 'context_reset';
  text?: string;
  delta?: string;
  audio?: string;
  error?: string;
  timestamp?: number;
}

export class TunnelClient {
  private ws: WebSocket | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = Infinity; // Keep trying forever
  private terminalInputHandler: ((sessionId: string, data: string) => void) | null = null;
  private agentRequestHandler: ((request: AgentRequest) => Promise<void>) | null = null;
  private lastPongReceived: number = 0;
  private pingInterval: NodeJS.Timeout | null = null;
  private healthCheckInterval: NodeJS.Timeout | null = null;
  private connectionState: ConnectionState = ConnectionState.Disconnected;
  private stateChangeCallback: ((state: ConnectionState) => void) | null = null;
  
  // NEW: Agent WebSocket handlers for unified protocol
  private agentWsHandlers = new Map<string, AgentWebSocketHandler>();
  
  // Heartbeat configuration
  private readonly PING_INTERVAL_MS = 20000; // 20 seconds
  private readonly PONG_TIMEOUT_MS = 30000; // 30 seconds
  
  constructor(
    private config: TunnelConfig,
    private requestHandler: (req: TunnelRequest) => Promise<TunnelResponse>,
    private clientAuthKey?: string,
    private openaiApiKey?: string
  ) {}
  
  setTerminalInputHandler(handler: (sessionId: string, data: string) => void): void {
    this.terminalInputHandler = handler;
  }
  
  setAgentRequestHandler(handler: (request: AgentRequest) => Promise<void>): void {
    this.agentRequestHandler = handler;
  }
  
  setStateChangeCallback(callback: (state: ConnectionState) => void): void {
    this.stateChangeCallback = callback;
  }
  
  /**
   * NEW: Send AgentEvent to client via unified protocol
   */
  sendAgentEvent(event: AgentEvent): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      console.warn('⚠️ Cannot send agent_event - WebSocket not connected');
      return;
    }
    
    const message = {
      type: 'agent_event',
      event
    };
    
    console.log(`📤 TunnelClient: Sending agent_event: ${event.type}, session=${event.session_id}`);
    this.ws.send(JSON.stringify(message));
  }

  /**
   * LEGACY: Send agent response back to tunnel server (DEPRECATED)
   */
  sendAgentResponse(tunnelId: string, streamKey: string, payload: AgentResponsePayload): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      console.warn('⚠️ Cannot send agent_response - WebSocket not connected');
      return;
    }
    
    const message = {
      type: 'agent_response',
      tunnelId,
      streamKey,
      payload
    };
    
    const messageStr = JSON.stringify(message);
    console.log(`📤 TunnelClient: Sending agent_response: type=${payload.type}, streamKey=${streamKey}`);
    
    this.ws.send(messageStr);
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
    payload: { text: string; delta: string; raw?: string; timestamp: number; isComplete?: boolean; isTTSReady?: boolean }
  ): void {
    if (!this.ws) {
      console.error(`❌❌❌ TunnelClient: WebSocket is null, cannot send recording_output`);
      return;
    }
    
    if (this.ws.readyState !== WebSocket.OPEN) {
      console.warn(`⚠️⚠️⚠️ TunnelClient: Cannot send recording_output - WebSocket not OPEN, state=${this.ws.readyState} (1=OPEN, 0=CONNECTING, 2=CLOSING, 3=CLOSED)`);
      return;
    }
    
    // If this is a tts_ready event, send it as tts_ready type
    if (payload.isTTSReady === true) {
      const ttsMessage = {
        type: 'tts_ready',
        session_id: sessionId,
        text: payload.text,
        timestamp: payload.timestamp
      };
      const messageStr = JSON.stringify(ttsMessage);
      console.log(`🎙️🎙️🎙️ TunnelClient: Sending tts_ready event to tunnel: sessionId=${sessionId}, text=${payload.text.length} chars`);
      
      try {
        this.ws.send(messageStr, (error) => {
          if (error) {
            console.error(`❌❌❌ TunnelClient: Error sending tts_ready: ${error.message}`);
          } else {
            console.log(`✅✅✅ TunnelClient: Successfully sent tts_ready event (${messageStr.length} bytes)`);
          }
        });
      } catch (error) {
        console.error(`❌❌❌ TunnelClient: Exception while sending tts_ready: ${error}`);
      }
      return;
    }
    
    // Legacy format for streaming messages
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
        } else if (message.type === 'agent_event') {
          // NEW: Handle AgentEvent via unified protocol
          console.log(`🤖 TunnelClient: Received agent_event: ${message.event?.type}, session=${message.event?.session_id}`);
          const event = message.event as AgentEvent;
          
          if (!this.openaiApiKey) {
            console.error('❌ TunnelClient: Cannot handle agent_event - OpenAI API key not configured');
            return;
          }
          
          // Create or get handler for this session
          if (!this.agentWsHandlers.has(event.session_id)) {
            const handler = new AgentWebSocketHandler(
              event.session_id,
              this.openaiApiKey,
              (responseEvent: AgentEvent) => this.sendAgentEvent(responseEvent) // Emit callback
            );
            this.agentWsHandlers.set(event.session_id, handler);
          }
          
          // Process event
          const handler = this.agentWsHandlers.get(event.session_id);
          if (handler) {
            handler.handleEvent(event).catch(error => {
              console.error(`❌ TunnelClient: Error processing agent_event: ${error.message}`);
            });
          }
        } else if (message.type === 'agent_request') {
          // LEGACY: Handle agent request from iPhone via tunnel (DEPRECATED)
          console.log(`🤖 TunnelClient: Received LEGACY agent_request from tunnel: type=${message.payload?.type}`);
          if (this.agentRequestHandler) {
            this.agentRequestHandler(message as AgentRequest).catch(error => {
              console.error(`❌ TunnelClient: Error handling agent_request: ${error.message}`);
              // Send error response back
              this.sendAgentResponse(message.tunnelId, message.streamKey, {
                type: 'error',
                error: error.message || 'Unknown error',
                timestamp: Date.now()
              });
            });
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
