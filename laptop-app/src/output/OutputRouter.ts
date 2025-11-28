import type { TerminalManager } from '../terminal/TerminalManager';
import type { TunnelClient } from '../tunnel/TunnelClient';
import type { TTSProvider } from '../keys/TTSProvider';
import type { ChatMessage } from '../terminal/types';
import { synthesizeSpeech } from '../proxy/TTSProxy';

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

export interface SessionTtsSettings {
  enabled: boolean;
  speed: number;
  language: string;
}

/**
 * Routes terminal output to appropriate destinations
 * - terminal_display: Raw/filtered output for terminal UI (mobile + web)
 * - recording_stream: Processed output for TTS (mobile only)
 * - websocket: Output for localhost WebSocket connections
 */
export class OutputRouter {
  private websocketListeners = new Map<string, Set<(data: string) => void>>();
  private sessionTtsSettings = new Map<string, SessionTtsSettings>();
  private ttsProvider: TTSProvider | null = null;
  
  constructor(
    private terminalManager: TerminalManager,
    private tunnelClient: TunnelClient | null
  ) {}

  /**
   * Set TTS provider for server-side TTS synthesis
   */
  setTtsProvider(provider: TTSProvider | null): void {
    this.ttsProvider = provider;
  }

  /**
   * Set TTS settings for a session
   */
  setSessionTtsSettings(sessionId: string, settings: SessionTtsSettings): void {
    this.sessionTtsSettings.set(sessionId, settings);
    console.log(`🔊 [OutputRouter] TTS settings for ${sessionId}: enabled=${settings.enabled}, speed=${settings.speed}, language=${settings.language}`);
  }

  /**
   * Get TTS settings for a session
   */
  getSessionTtsSettings(sessionId: string): SessionTtsSettings | undefined {
    return this.sessionTtsSettings.get(sessionId);
  }

  /**
   * Clear TTS settings for a session
   */
  clearSessionTtsSettings(sessionId: string): void {
    this.sessionTtsSettings.delete(sessionId);
  }

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
   * Now supports server-side TTS synthesis
   */
  private sendToRecordingStream(message: OutputMessage): void {
    // If this is a complete message (TTS ready), synthesize and send audio
    if (message.metadata?.isComplete === true) {
      const text = message.metadata?.fullText || message.data;
      const settings = this.sessionTtsSettings.get(message.sessionId);
      
      // If TTS is enabled and we have a provider, synthesize audio
      if (settings?.enabled !== false && this.ttsProvider) {
        this.synthesizeAndSendTTS(message.sessionId, text, settings);
      } else {
        // TTS disabled - just send text event for legacy clients
        this.sendTtsTextEvent(message.sessionId, text);
      }
      return;
    }

    // Legacy format for streaming messages (for clients that still use it)
    if (this.tunnelClient) {
      const payload = {
        text: message.metadata?.fullText || message.data,
        delta: message.metadata?.delta || message.data,
        raw: message.data,
        timestamp: Date.now(),
        isComplete: message.metadata?.isComplete || false
      };
      this.tunnelClient.sendRecordingOutput(message.sessionId, payload);
    }
  }

  /**
   * Synthesize TTS audio and send via WebSocket/Tunnel
   */
  private async synthesizeAndSendTTS(
    sessionId: string,
    text: string,
    settings?: SessionTtsSettings
  ): Promise<void> {
    if (!this.ttsProvider) {
      console.warn(`⚠️ [OutputRouter] No TTS provider configured, sending text only`);
      this.sendTtsTextEvent(sessionId, text);
      return;
    }

    const speed = settings?.speed ?? 1.0;
    
    try {
      console.log(`🔊 [OutputRouter] Synthesizing TTS for session ${sessionId}: ${text.length} chars at ${speed}x speed`);
      
      // Synthesize audio
      const audioBuffer = await synthesizeSpeech(this.ttsProvider, text, undefined, speed);
      const audioBase64 = audioBuffer.toString('base64');
      
      console.log(`✅ [OutputRouter] TTS synthesis complete: ${audioBuffer.length} bytes`);
      
      // Create tts_audio event
      const ttsAudioEvent = {
        type: 'tts_audio',
        session_id: sessionId,
        audio: audioBase64,
        format: 'audio/mpeg',
        text: text,
        timestamp: Date.now()
      };
      
      const jsonString = JSON.stringify(ttsAudioEvent);
      
      // Send to WebSocket listeners (localhost)
      const listeners = this.websocketListeners.get(sessionId);
      if (listeners && listeners.size > 0) {
        console.log(`📤 [OutputRouter] Sending tts_audio to ${listeners.size} WebSocket listeners`);
        listeners.forEach(listener => listener(jsonString));
      }
      
      // Send to tunnel (for mobile via tunnel server)
      if (this.tunnelClient) {
        console.log(`📤 [OutputRouter] Sending tts_audio via tunnel`);
        this.tunnelClient.sendTerminalOutput(sessionId, jsonString);
      }
      
      // Clear TTS settings after sending
      this.clearSessionTtsSettings(sessionId);
      
    } catch (error) {
      console.error(`❌ [OutputRouter] TTS synthesis error:`, error);
      // Fallback to text-only event
      this.sendTtsTextEvent(sessionId, text);
    }
  }

  /**
   * Send TTS text event (for legacy clients or when TTS is disabled)
   */
  private sendTtsTextEvent(sessionId: string, text: string): void {
    const ttsReadyEvent = {
      type: 'tts_ready',
      session_id: sessionId,
      text: text,
      timestamp: Date.now()
    };
    
    const jsonString = JSON.stringify(ttsReadyEvent);
    
    // Send to WebSocket listeners
    const listeners = this.websocketListeners.get(sessionId);
    if (listeners) {
      listeners.forEach(listener => listener(jsonString));
    }
    
    // Send to tunnel
    if (this.tunnelClient) {
      this.tunnelClient.sendRecordingOutput(sessionId, {
        text: text,
        delta: '',
        raw: '',
        timestamp: Date.now(),
        isComplete: true,
        isTTSReady: true
      });
    }
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
