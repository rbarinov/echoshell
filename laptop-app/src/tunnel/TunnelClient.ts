import { WebSocket } from 'ws';

export class TunnelClient {
  private ws: WebSocket | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;
  
  constructor(
    private config: any,
    private requestHandler: (req: any) => Promise<any>
  ) {}
  
  async connect(): Promise<void> {
    const wsUrl = `${this.config.wsUrl}?api_key=${this.config.apiKey}`;
    
    console.log(`📡 Connecting to tunnel: ${wsUrl}`);
    
    this.ws = new WebSocket(wsUrl);
    
    this.ws.on('open', () => {
      console.log('✅ Tunnel connected');
      this.reconnectAttempts = 0;
    });
    
    this.ws.on('message', async (data) => {
      try {
        const message = JSON.parse(data.toString());
        
        if (message.type === 'http_request') {
          const response = await this.requestHandler(message);
          
          // Send response back through tunnel
          this.ws?.send(JSON.stringify({
            type: 'http_response',
            requestId: message.requestId,
            statusCode: response.statusCode || 200,
            body: response.body
          }));
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
      return;
    }
    
    this.reconnectAttempts++;
    const delay = Math.pow(2, this.reconnectAttempts) * 1000;
    
    console.log(`🔄 Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts})`);
    
    setTimeout(() => {
      this.connect();
    }, delay);
  }
  
  disconnect(): void {
    this.ws?.close();
  }
}
