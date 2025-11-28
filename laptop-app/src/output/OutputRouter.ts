import type { TerminalManager } from '../terminal/TerminalManager';
import type { TunnelClient } from '../tunnel/TunnelClient';
import type { ChatMessage } from '../terminal/types';

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

    // If this is a complete message (TTS ready), send as tts_ready event
    if (message.metadata?.isComplete === true) {
      const ttsPayload = {
        type: 'tts_ready',
        session_id: message.sessionId,
        text: message.metadata?.fullText || message.data,
        timestamp: Date.now()
      };
      
      // Send tts_ready event via tunnel client
      this.tunnelClient.sendRecordingOutput(message.sessionId, {
        ...ttsPayload,
        text: ttsPayload.text,
        delta: '',
        raw: '',
        timestamp: ttsPayload.timestamp,
        isComplete: true,
        isTTSReady: true // Flag to indicate this is a tts_ready event
      });
      return;
    }

    // Legacy format for streaming messages
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
   * Send chat message for headless terminals
   * Sends structured chat_message format instead of raw output
   */
  sendChatMessage(sessionId: string, message: ChatMessage): void {
    // Format: chat_message event for WebSocket and tunnel
    const chatEvent = {
      type: 'chat_message',
      session_id: sessionId,
      message: message,
      timestamp: Date.now(),
    };

    // Send to tunnel (for mobile)
    if (this.tunnelClient) {
      // Tunnel client needs to support chat messages
      // For now, send as JSON string (will be updated in tunnel client later)
      this.tunnelClient.sendTerminalOutput(sessionId, JSON.stringify(chatEvent));
    }

    // Send to WebSocket listeners (for localhost web UI)
    const listeners = this.websocketListeners.get(sessionId);
    if (listeners) {
      const jsonString = JSON.stringify(chatEvent);
      listeners.forEach(listener => listener(jsonString));
    }
  }

  /**
   * Update tunnel client reference
   */
  setTunnelClient(tunnelClient: TunnelClient | null): void {
    this.tunnelClient = tunnelClient;
  }
}
