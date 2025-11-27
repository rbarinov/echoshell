/**
 * Stream WebSocket handler
 * Handles terminal and recording stream connections from clients (iPhone)
 */

import { WebSocket } from 'ws';
import type { TerminalInputMessage } from '../../types/index.js';
import { TerminalInputMessageSchema } from '../../schemas/tunnelSchemas.js';
import { TunnelManager } from '../../tunnel/TunnelManager.js';
import { StreamManager } from './streamManager.js';
import { Logger } from '../../utils/logger.js';

/**
 * Handles stream WebSocket connections
 */
export class StreamHandler {
  constructor(
    private tunnelManager: TunnelManager,
    private streamManager: StreamManager
  ) {}

  /**
   * Handle terminal stream connection
   */
  handleTerminalStream(
    tunnelId: string,
    sessionId: string,
    ws: WebSocket,
    streamKey: string,
    connection: { ws: WebSocket; lastPongReceived: number }
  ): void {
    Logger.info('Terminal stream connected', { streamKey });

    this.streamManager.registerTerminalStream(streamKey, connection);

    // Handle input from client
    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString()) as TerminalInputMessage;
        const validation = TerminalInputMessageSchema.safeParse(message);

        if (!validation.success) {
          Logger.warn('Invalid terminal input message', {
            streamKey,
            issues: validation.error.issues,
          });
          return;
        }

        // Forward input to laptop via tunnel
        if (message.type === 'input') {
          const tunnel = this.tunnelManager.get(tunnelId);
          if (tunnel && tunnel.ws.readyState === WebSocket.OPEN) {
            tunnel.ws.send(
              JSON.stringify({
                type: 'terminal_input',
                sessionId,
                data: message.data,
              })
            );
            Logger.debug('Terminal input forwarded', { streamKey });
          } else {
            Logger.warn('Tunnel not available for terminal input', { tunnelId, streamKey });
          }
        }
      } catch (error) {
        Logger.error('Error processing terminal stream message', {
          streamKey,
          error: error instanceof Error ? error.message : 'Unknown error',
        });
      }
    });

    ws.on('close', () => {
      Logger.info('Terminal stream disconnected', { streamKey });
      this.streamManager.unregisterTerminalStream(streamKey, connection);
    });
  }

  /**
   * Handle recording stream connection
   */
  handleRecordingStream(
    streamKey: string,
    connection: { ws: WebSocket; lastPongReceived: number }
  ): void {
    Logger.info('Recording stream connected', { streamKey });

    this.streamManager.registerRecordingWsStream(streamKey, connection);

    connection.ws.on('close', () => {
      Logger.info('Recording stream disconnected', { streamKey });
      this.streamManager.unregisterRecordingWsStream(streamKey, connection);
    });
  }
}
