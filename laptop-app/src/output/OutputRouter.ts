import type { TerminalManager } from '../terminal/TerminalManager';
import type { TunnelClient } from '../tunnel/TunnelClient';

export interface OutputDestination {
  type: 'terminal_display' | 'recording_stream' | 'websocket';
  sessionId: string;
}

export interface OutputMessage {
  sessionId: string;
  data: string;
  destination: OutputDestination['type'];
  metadata?: {
    isComplete?: boolean;
    fullText?: string;
    delta?: string;
  };
}

/**
 * Routes terminal output to appropriate destinations
 * - terminal_display: Raw/filtered output for terminal UI (mobile + web)
 * - recording_stream: Processed output for TTS (mobile only)
 * - websocket: Output for localhost WebSocket connections
 */
export class OutputRouter {
  private websocketListeners = new Map<string, Set<(data: string) => void>>();
  
  constructor(
    private terminalManager: TerminalManager,
    private tunnelClient: TunnelClient | null
  ) {}

  /**
   * Register WebSocket listener for a session
   */
  addWebSocketListener(sessionId: string, listener: (data: string) => void): void {
    if (!this.websocketListeners.has(sessionId)) {
      this.websocketListeners.set(sessionId, new Set());
    }
    this.websocketListeners.get(sessionId)!.add(listener);
  }

  /**
   * Remove WebSocket listener
   */
  removeWebSocketListener(sessionId: string, listener: (data: string) => void): void {
    this.websocketListeners.get(sessionId)?.delete(listener);
  }

  /**
   * Route output to appropriate destinations
   */
  routeOutput(message: OutputMessage): void {
    switch (message.destination) {
      case 'terminal_display':
        this.sendToTerminalDisplay(message);
        break;
      case 'recording_stream':
        this.sendToRecordingStream(message);
        break;
      case 'websocket':
        this.sendToWebSocket(message);
        break;
    }
  }

  /**
   * Send output to terminal display (mobile + web via tunnel)
   */
  private sendToTerminalDisplay(message: OutputMessage): void {
    // Send to tunnel (for mobile)
    if (this.tunnelClient) {
      this.tunnelClient.sendTerminalOutput(message.sessionId, message.data);
    }
    
    // Send to WebSocket listeners (for localhost web UI)
    const listeners = this.websocketListeners.get(message.sessionId);
    if (listeners) {
      listeners.forEach(listener => listener(message.data));
    }
  }

  /**
   * Send output to recording stream (for TTS on mobile)
   */
  private sendToRecordingStream(message: OutputMessage): void {
    if (!this.tunnelClient) {
      return;
    }

    const payload = {
      text: message.metadata?.fullText || message.data,
      delta: message.metadata?.delta || message.data,
      raw: message.data,
      timestamp: Date.now(),
      isComplete: message.metadata?.isComplete || false
    };

    this.tunnelClient.sendRecordingOutput(message.sessionId, payload);
  }

  /**
   * Send output to WebSocket (localhost only)
   */
  private sendToWebSocket(message: OutputMessage): void {
    const listeners = this.websocketListeners.get(message.sessionId);
    if (listeners) {
      listeners.forEach(listener => listener(message.data));
    }
  }

  /**
   * Update tunnel client reference
   */
  setTunnelClient(tunnelClient: TunnelClient | null): void {
    this.tunnelClient = tunnelClient;
  }
}
