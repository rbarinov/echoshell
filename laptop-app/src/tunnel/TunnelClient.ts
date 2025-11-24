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

export class TunnelClient {
  private ws: WebSocket | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = Infinity; // Keep trying forever
  private terminalInputHandler: ((sessionId: string, data: string) => void) | null = null;
  
  constructor(
    private config: TunnelConfig,
    private requestHandler: (req: TunnelRequest) => Promise<TunnelResponse>,
    private clientAuthKey?: string
  ) {}
  
  setTerminalInputHandler(handler: (sessionId: string, data: string) => void): void {
    this.terminalInputHandler = handler;
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
    payload: { text: string; delta: string; raw?: string; timestamp: number }
  ): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({
        type: 'recording_output',
        sessionId,
        ...payload
      }));
    }
  }
  
  async connect(): Promise<void> {
    const wsUrl = `${this.config.wsUrl}?api_key=${this.config.apiKey}`;
    
    console.log(`📡 Connecting to tunnel: ${wsUrl}`);
    
    this.ws = new WebSocket(wsUrl);
    
    this.ws.on('open', () => {
      console.log('✅ Tunnel connected');
      this.reconnectAttempts = 0;
      
      if (this.clientAuthKey) {
        this.ws?.send(JSON.stringify({
          type: 'client_auth_key',
          key: this.clientAuthKey
        }));
      }
    });
    
    this.ws.on('message', async (data) => {
      try {
        const message = JSON.parse(data.toString());
        
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
      this.attemptReconnect();
    });
    
    this.ws.on('error', (error) => {
      console.error('❌ Tunnel error:', error);
    });
  }
  
  private attemptReconnect(): void {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error('❌ Max reconnection attempts reached');
      console.log('💡 Please restart the application or check tunnel server');
      return;
    }
    
    this.reconnectAttempts++;
    const delay = Math.min(Math.pow(2, this.reconnectAttempts) * 1000, 30000); // Max 30s
    
    console.log(`🔄 Reconnecting to tunnel in ${delay / 1000}s (attempt ${this.reconnectAttempts}${this.maxReconnectAttempts === Infinity ? '' : '/' + this.maxReconnectAttempts})`);
    
    setTimeout(() => {
      console.log('🔌 Attempting to reconnect...');
      this.connect().catch(err => {
        console.error('❌ Reconnection failed:', err.message);
      });
    }, delay);
  }
  
  disconnect(): void {
    this.ws?.close();
  }
}
