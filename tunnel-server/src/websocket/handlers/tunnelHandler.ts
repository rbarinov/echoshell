/**
 * Tunnel WebSocket handler
 * Handles messages from laptop tunnel connections
 */

import type { WebSocket } from 'ws';
import type { Express, Response } from 'express';
import type {
  WebSocketMessage,
  HttpResponseMessage,
  ClientAuthKeyMessage,
  TerminalOutputMessage,
  RecordingOutputMessage,
  TTSReadyMessage,
  AgentResponseMessage,
  AgentEventMessage,
} from '../../types/index.js';
import {
  HttpResponseMessageSchema,
  ClientAuthKeyMessageSchema,
  TerminalOutputMessageSchema,
  RecordingOutputMessageSchema,
  TTSReadyMessageSchema,
  AgentResponseMessageSchema,
  AgentEventMessageSchema,
} from '../../schemas/tunnelSchemas.js';
import { TunnelManager } from '../../tunnel/TunnelManager.js';
import { Logger } from '../../utils/logger.js';
import { StreamManager } from './streamManager.js';

/**
 * Handles tunnel WebSocket messages
 */
export class TunnelHandler {
  constructor(
    private tunnelManager: TunnelManager,
    private streamManager: StreamManager,
    private pendingRequests: Map<string, Response>
  ) {}

  /**
   * Handle WebSocket message from tunnel
   */
  handleMessage(tunnelId: string, data: Buffer | string): void {
    try {
      const rawMessage = data.toString();
      let message: WebSocketMessage;

      try {
        message = JSON.parse(rawMessage) as WebSocketMessage;
      } catch (parseError) {
        Logger.error('Failed to parse WebSocket message', {
          tunnelId,
          error: parseError instanceof Error ? parseError.message : 'Unknown error',
          rawMessage: rawMessage.substring(0, 500),
        });
        return;
      }

      Logger.debug('Received WebSocket message', {
        tunnelId,
        messageType: message.type,
      });

      // Route message to appropriate handler
      switch (message.type) {
        case 'http_response':
          this.handleHttpResponse(message as HttpResponseMessage);
          break;
        case 'client_auth_key':
          this.handleClientAuthKey(tunnelId, message as ClientAuthKeyMessage);
          break;
        case 'terminal_output':
          this.handleTerminalOutput(tunnelId, message as TerminalOutputMessage);
          break;
        case 'recording_output':
          this.handleRecordingOutput(tunnelId, message as RecordingOutputMessage);
          break;
        case 'tts_ready':
          this.handleTTSReady(tunnelId, message as TTSReadyMessage);
          break;
        case 'agent_response':
          this.handleAgentResponse(tunnelId, message as AgentResponseMessage);
          break;
        case 'agent_event':
          this.handleAgentEvent(tunnelId, message as AgentEventMessage);
          break;
        default:
          Logger.debug('Unknown message type', { tunnelId, messageType: message.type });
      }
    } catch (error) {
      Logger.error('Error processing tunnel message', {
        tunnelId,
        error: error instanceof Error ? error.message : 'Unknown error',
      });
    }
  }

  /**
   * Handle HTTP response from laptop
   */
  private handleHttpResponse(message: HttpResponseMessage): void {
      const validation = HttpResponseMessageSchema.safeParse(message);
      if (!validation.success) {
        Logger.warn('Invalid HTTP response message', { issues: validation.error.issues });
        return;
      }

    const res = this.pendingRequests.get(message.requestId);
    if (res) {
      res.status(message.statusCode || 200).json(message.body);
      this.pendingRequests.delete(message.requestId);
      Logger.debug('HTTP response sent', { requestId: message.requestId });
    } else {
      Logger.warn('No pending request found for response', { requestId: message.requestId });
    }
  }

  /**
   * Handle client auth key registration
   */
  private handleClientAuthKey(tunnelId: string, message: ClientAuthKeyMessage): void {
      const validation = ClientAuthKeyMessageSchema.safeParse(message);
      if (!validation.success) {
        Logger.warn('Invalid client auth key message', {
          tunnelId,
          issues: validation.error.issues,
        });
        return;
      }

    this.tunnelManager.setClientAuthKey(tunnelId, message.key);
    Logger.info('Client auth key registered', { tunnelId });
  }

  /**
   * Handle terminal output from laptop
   */
  private handleTerminalOutput(tunnelId: string, message: TerminalOutputMessage): void {
      const validation = TerminalOutputMessageSchema.safeParse(message);
      if (!validation.success) {
        Logger.warn('Invalid terminal output message', {
          tunnelId,
          issues: validation.error.issues,
        });
        return;
      }

    const streamKey = `${tunnelId}:${message.sessionId}`;
    
    // Check if data is already a chat_message JSON string (from OutputRouter.sendChatMessage)
    try {
      const parsedData = JSON.parse(message.data);
      if (parsedData && typeof parsedData === 'object' && parsedData.type === 'chat_message') {
        // This is a chat_message, forward it as-is
        Logger.debug('Forwarding chat_message', { tunnelId, sessionId: message.sessionId });
        this.streamManager.broadcastToTerminalStream(streamKey, message.data);
        return;
      }
    } catch {
      // Not JSON or not chat_message, continue with normal formatting
    }
    
    // Regular terminal output format
    const formattedMessage = JSON.stringify({
      type: 'output',
      session_id: message.sessionId,
      data: message.data,
      timestamp: Date.now(),
    });

    this.streamManager.broadcastToTerminalStream(streamKey, formattedMessage);
  }

  /**
   * Handle recording output from laptop
   */
  private handleRecordingOutput(tunnelId: string, message: RecordingOutputMessage): void {
      const validation = RecordingOutputMessageSchema.safeParse(message);
      if (!validation.success) {
        Logger.warn('Invalid recording output message', {
          tunnelId,
          issues: validation.error.issues,
        });
        return;
      }

    const streamKey = `${tunnelId}:${message.sessionId}:recording`;
    
    // Check if this is a tts_ready event (isComplete === true with text)
    // Send as tts_ready event instead of recording_output
    if (message.isComplete === true && message.text) {
      const ttsPayload = {
        type: 'tts_ready',
        session_id: message.sessionId,
        text: message.text,
        timestamp: message.timestamp ?? Date.now(),
      };
      const payloadString = JSON.stringify(ttsPayload);
      Logger.debug('Sending tts_ready event', { tunnelId, sessionId: message.sessionId, textLength: message.text.length });
      this.streamManager.broadcastToRecordingStream(streamKey, payloadString);
      return;
    }
    
    // Regular recording output format
    const payload: Record<string, unknown> = {
      type: 'recording_output',
      session_id: message.sessionId,
      text: message.text || '',
      delta: message.delta || '',
      raw: message.raw,
      timestamp: message.timestamp ?? Date.now(),
    };

    // Only include isComplete if it was present in the original message
    if (message.isComplete !== undefined && message.isComplete !== null) {
      payload.isComplete = message.isComplete;
    }

    const payloadString = JSON.stringify(payload);

    Logger.debug('Forwarding recording output', {
      tunnelId,
      sessionId: message.sessionId,
      hasIsComplete: message.isComplete !== undefined,
    });

    this.streamManager.broadcastToRecordingStream(streamKey, payloadString);
  }

  /**
   * Handle TTS ready event from laptop
   * Broadcasts to all recording streams for the session
   */
  private handleTTSReady(tunnelId: string, message: TTSReadyMessage): void {
    const validation = TTSReadyMessageSchema.safeParse(message);
    if (!validation.success) {
      Logger.warn('Invalid tts_ready message', {
        tunnelId,
        issues: validation.error.issues,
      });
      return;
    }

    const sessionId = message.session_id;
    const streamKey = `${tunnelId}:${sessionId}:recording`;

    Logger.info('TTS ready event received', {
      tunnelId,
      sessionId,
      textLength: message.text.length,
    });

    // Create tts_ready event for iOS clients
    const ttsPayload = {
      type: 'tts_ready',
      session_id: sessionId,
      text: message.text,
      timestamp: message.timestamp ?? Date.now(),
    };

    const payloadString = JSON.stringify(ttsPayload);

    // Broadcast to all recording streams for this session
    this.streamManager.broadcastToRecordingStream(streamKey, payloadString);

    Logger.debug('TTS ready event broadcasted', {
      tunnelId,
      sessionId,
      streamKey,
    });
  }

  /**
   * Handle agent response from laptop
   * Forwards agent response messages (transcription, chunk, complete) to iPhone
   * LEGACY - will be deprecated in favor of handleAgentEvent
   */
  private handleAgentResponse(tunnelId: string, message: AgentResponseMessage): void {
    const validation = AgentResponseMessageSchema.safeParse(message);
    if (!validation.success) {
      Logger.warn('Invalid agent_response message', {
        tunnelId,
        issues: validation.error.issues,
      });
      return;
    }

    const streamKey = message.streamKey || `${tunnelId}:agent`;

    Logger.debug('Agent response received', {
      tunnelId,
      streamKey,
      payloadType: message.payload?.type,
    });

    // Forward payload directly to the agent stream client
    const payloadString = JSON.stringify(message.payload);
    this.streamManager.broadcastToAgentStream(streamKey, payloadString);
  }

  /**
   * Handle unified AgentEvent from laptop (NEW protocol)
   * Routes event to all clients subscribed to this session
   */
  private handleAgentEvent(tunnelId: string, message: AgentEventMessage): void {
    const validation = AgentEventMessageSchema.safeParse(message);
    if (!validation.success) {
      Logger.warn('Invalid agent_event message', {
        tunnelId,
        issues: validation.error.issues,
      });
      return;
    }

    const event = message.event;
    const streamKey = `${tunnelId}:${event.session_id}:agent`;

    Logger.info('AgentEvent received', {
      tunnelId,
      sessionId: event.session_id,
      eventType: event.type,
      streamKey,
    });

    // Broadcast event to all clients subscribed to this agent stream
    // Clients will receive the AgentEvent directly
    this.streamManager.broadcastToAgentStream(streamKey, JSON.stringify(event));

    Logger.debug('AgentEvent broadcasted', {
      tunnelId,
      sessionId: event.session_id,
      eventType: event.type,
    });
  }
}
