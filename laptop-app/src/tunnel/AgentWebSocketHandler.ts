/**
 * Agent WebSocket Handler
 * 
 * Manages unified /agent/ws WebSocket connection for AgentEvent protocol
 * This is used WITHIN TunnelClient to handle AgentEvents
 */

import { WebSocket } from 'ws';
import { AgentEvent } from '../types/AgentEvent.js';
import { AgentEventHandler, AgentEventEmitter } from '../agent/AgentEventHandler.js';
import logger from '../utils/logger.js';

export class AgentWebSocketHandler {
  private eventHandler: AgentEventHandler;

  constructor(
    private sessionId: string,
    openaiApiKey: string,
    private emit: (event: AgentEvent) => void // Callback to emit events via TunnelClient
  ) {
    // Create event handler with emitter callback
    const emitter: AgentEventEmitter = (event: AgentEvent) => {
      this.emit(event);
    };

    this.eventHandler = new AgentEventHandler(emitter, openaiApiKey);
  }

  /**
   * Process incoming AgentEvent
   */
  async handleEvent(event: AgentEvent): Promise<void> {
    try {
      // Validate session_id matches
      if (event.session_id !== this.sessionId) {
        logger.warn('Session ID mismatch', { 
          expected: this.sessionId, 
          received: event.session_id 
        });
        return;
      }

      await this.eventHandler.handleEvent(event);
    } catch (err) {
      const error = err instanceof Error ? err : new Error(String(err));
      logger.error('Failed to process event', error, { sessionId: this.sessionId });
    }
  }
}

