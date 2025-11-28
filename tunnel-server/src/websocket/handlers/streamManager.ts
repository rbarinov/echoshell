/**
 * Stream connection management
 * Manages terminal and recording stream connections
 */

import type { StreamConnection } from '../../types/index.js';
import type { Express, Response } from 'express';
import { WebSocket } from 'ws';
import { Logger } from '../../utils/logger.js';

/**
 * Manages stream connections (terminal and recording)
 */
export class StreamManager {
  private terminalStreams = new Map<string, Set<StreamConnection>>();
  private recordingWsStreams = new Map<string, Set<StreamConnection>>();
  private recordingSseStreams = new Map<string, Set<Response>>();

  /**
   * Register terminal stream connection
   */
  registerTerminalStream(streamKey: string, connection: StreamConnection): void {
    if (!this.terminalStreams.has(streamKey)) {
      this.terminalStreams.set(streamKey, new Set());
    }
    this.terminalStreams.get(streamKey)!.add(connection);
    Logger.info('Terminal stream registered', { streamKey });
  }

  /**
   * Unregister terminal stream connection
   */
  unregisterTerminalStream(streamKey: string, connection: StreamConnection): void {
    this.terminalStreams.get(streamKey)?.delete(connection);
    if (this.terminalStreams.get(streamKey)?.size === 0) {
      this.terminalStreams.delete(streamKey);
    }
    Logger.info('Terminal stream unregistered', { streamKey });
  }

  /**
   * Register recording WebSocket stream connection
   */
  registerRecordingWsStream(streamKey: string, connection: StreamConnection): void {
    if (!this.recordingWsStreams.has(streamKey)) {
      this.recordingWsStreams.set(streamKey, new Set());
    }
    this.recordingWsStreams.get(streamKey)!.add(connection);
    Logger.info('Recording WebSocket stream registered', { streamKey });
  }

  /**
   * Unregister recording WebSocket stream connection
   */
  unregisterRecordingWsStream(streamKey: string, connection: StreamConnection): void {
    this.recordingWsStreams.get(streamKey)?.delete(connection);
    if (this.recordingWsStreams.get(streamKey)?.size === 0) {
      this.recordingWsStreams.delete(streamKey);
    }
    Logger.info('Recording WebSocket stream unregistered', { streamKey });
  }

  /**
   * Register recording SSE stream connection
   */
  registerRecordingSseStream(streamKey: string, response: Response): void {
    if (!this.recordingSseStreams.has(streamKey)) {
      this.recordingSseStreams.set(streamKey, new Set());
    }
    this.recordingSseStreams.get(streamKey)!.add(response);
    Logger.info('Recording SSE stream registered', { streamKey });
  }

  /**
   * Unregister recording SSE stream connection
   */
  unregisterRecordingSseStream(streamKey: string, response: Response): void {
    this.recordingSseStreams.get(streamKey)?.delete(response);
    if (this.recordingSseStreams.get(streamKey)?.size === 0) {
      this.recordingSseStreams.delete(streamKey);
    }
    Logger.info('Recording SSE stream unregistered', { streamKey });
  }

  /**
   * Broadcast message to terminal stream
   */
  broadcastToTerminalStream(streamKey: string, message: string): void {
    const clients = this.terminalStreams.get(streamKey);
    if (!clients || clients.size === 0) {
      return;
    }

    let sentCount = 0;
    clients.forEach((conn) => {
      if (conn.ws.readyState === WebSocket.OPEN) {
        conn.ws.send(message);
        sentCount++;
      }
    });

    if (sentCount > 0) {
      Logger.debug('Broadcast to terminal stream', { streamKey, sentCount, total: clients.size });
    }
  }

  /**
   * Broadcast message to recording stream (WebSocket + SSE)
   */
  broadcastToRecordingStream(streamKey: string, payload: string): void {
    // Broadcast to WebSocket clients
    const wsClients = this.recordingWsStreams.get(streamKey);
    if (wsClients && wsClients.size > 0) {
      let sentCount = 0;
      wsClients.forEach((conn) => {
        if (conn.ws.readyState === WebSocket.OPEN) {
          conn.ws.send(payload);
          sentCount++;
        }
      });
      Logger.debug('Broadcast to recording WebSocket stream', {
        streamKey,
        sentCount,
        total: wsClients.size,
      });
    }

    // Broadcast to SSE clients
    const sseClients = this.recordingSseStreams.get(streamKey);
    if (sseClients && sseClients.size > 0) {
      sseClients.forEach((client) => {
        try {
          client.write(`event: recording_output\n`);
          client.write(`data: ${payload}\n\n`);
        } catch (error) {
          Logger.warn('Failed to write to SSE client', {
            streamKey,
            error: error instanceof Error ? error.message : 'Unknown error',
          });
        }
      });
      Logger.debug('Broadcast to recording SSE stream', { streamKey, count: sseClients.size });
    }
  }

  /**
   * Get terminal stream connections for a stream key
   */
  getTerminalStream(streamKey: string): Set<StreamConnection> | undefined {
    return this.terminalStreams.get(streamKey);
  }

  /**
   * Get recording WebSocket stream connections for a stream key
   */
  getRecordingWsStream(streamKey: string): Set<StreamConnection> | undefined {
    return this.recordingWsStreams.get(streamKey);
  }

  /**
   * Get terminal streams map (for heartbeat)
   */
  getTerminalStreamsMap(): Map<string, Set<StreamConnection>> {
    return this.terminalStreams;
  }

  /**
   * Get recording WebSocket streams map (for heartbeat)
   */
  getRecordingWsStreamsMap(): Map<string, Set<StreamConnection>> {
    return this.recordingWsStreams;
  }

  /**
   * Gracefully shutdown all stream connections
   * Closes all WebSocket connections and clears all intervals
   */
  shutdown(): void {
    Logger.info('Shutting down StreamManager', {
      terminalStreams: this.terminalStreams.size,
      recordingWsStreams: this.recordingWsStreams.size,
      recordingSseStreams: this.recordingSseStreams.size,
    });

    // Close terminal streams
    for (const [streamKey, connections] of this.terminalStreams) {
      for (const conn of connections) {
        try {
          // Clear intervals
          if (conn.pingInterval) {
            clearInterval(conn.pingInterval);
          }
          if (conn.healthCheckInterval) {
            clearInterval(conn.healthCheckInterval);
          }
          // Close WebSocket
          if (conn.ws.readyState === 1) { // WebSocket.OPEN
            conn.ws.close(1001, 'Server shutting down');
          }
        } catch (error) {
          Logger.warn('Error closing terminal stream', {
            streamKey,
            error: error instanceof Error ? error.message : 'Unknown error',
          });
        }
      }
    }

    // Close recording WebSocket streams
    for (const [streamKey, connections] of this.recordingWsStreams) {
      for (const conn of connections) {
        try {
          // Clear intervals
          if (conn.pingInterval) {
            clearInterval(conn.pingInterval);
          }
          if (conn.healthCheckInterval) {
            clearInterval(conn.healthCheckInterval);
          }
          // Close WebSocket
          if (conn.ws.readyState === 1) { // WebSocket.OPEN
            conn.ws.close(1001, 'Server shutting down');
          }
        } catch (error) {
          Logger.warn('Error closing recording stream', {
            streamKey,
            error: error instanceof Error ? error.message : 'Unknown error',
          });
        }
      }
    }

    // End SSE streams
    for (const [streamKey, responses] of this.recordingSseStreams) {
      for (const res of responses) {
        try {
          res.end();
        } catch (error) {
          Logger.warn('Error closing SSE stream', {
            streamKey,
            error: error instanceof Error ? error.message : 'Unknown error',
          });
        }
      }
    }

    // Clear all maps
    this.terminalStreams.clear();
    this.recordingWsStreams.clear();
    this.recordingSseStreams.clear();

    Logger.info('StreamManager shutdown complete');
  }
}
