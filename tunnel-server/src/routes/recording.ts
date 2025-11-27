/**
 * Recording stream routes (SSE)
 */

import type { Express, Request, Response } from 'express';
import { TunnelManager } from '../tunnel/TunnelManager.js';
import { StreamManager } from '../websocket/handlers/streamManager.js';
import { TunnelNotFoundError, TunnelAuthError } from '../errors/TunnelError.js';
import { Logger } from '../utils/logger.js';

/**
 * Setup recording stream routes
 */
export function setupRecordingRoutes(
  app: Express,
  tunnelManager: TunnelManager,
  streamManager: StreamManager
): void {
  app.get('/api/:tunnelId/recording/:sessionId/events', (req: Request, res: Response) => {
    try {
      const { tunnelId, sessionId } = req.params;
      const tunnel = tunnelManager.get(tunnelId);

      if (!tunnel) {
        throw new TunnelNotFoundError(tunnelId);
      }

      if (!tunnel.clientAuthKey) {
        throw new TunnelAuthError('Tunnel auth key not registered yet');
      }

      const providedKey = req.header('X-Laptop-Auth-Key');
      if (!providedKey || providedKey !== tunnel.clientAuthKey) {
        throw new TunnelAuthError('Invalid or missing X-Laptop-Auth-Key header');
      }

      const streamKey = `${tunnelId}:${sessionId}:recording`;
      Logger.info('SSE recording stream connected', { streamKey });

      // Setup SSE headers
      res.setHeader('Content-Type', 'text/event-stream');
      res.setHeader('Cache-Control', 'no-cache');
      res.setHeader('Connection', 'keep-alive');
      res.setHeader('X-Accel-Buffering', 'no');
      req.socket.setTimeout(0);
      req.socket.setKeepAlive(true);
      res.write('\n');

      // Register SSE stream
      streamManager.registerRecordingSseStream(streamKey, res);

      // Handle disconnect
      req.on('close', () => {
        Logger.info('SSE recording stream disconnected', { streamKey });
        res.end();
        streamManager.unregisterRecordingSseStream(streamKey, res);
      });
    } catch (error) {
      if (error instanceof TunnelNotFoundError || error instanceof TunnelAuthError) {
        res.status(error.statusCode).json({
          error: error.code,
          message: error.message,
        });
      } else {
        Logger.error('Error setting up SSE recording stream', {
          error: error instanceof Error ? error.message : 'Unknown error',
        });
        res.status(500).json({ error: 'Internal server error' });
      }
    }
  });
}
