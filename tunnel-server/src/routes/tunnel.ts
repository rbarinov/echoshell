/**
 * Tunnel creation routes
 */

import type { Express, Request, Response } from 'express';
import { TunnelCreateRequestSchema } from '../schemas/tunnelSchemas.js';
import { TunnelAuthError, InvalidRequestError } from '../errors/TunnelError.js';
import { Config } from '../config/Config.js';
import { Logger } from '../utils/logger.js';
import crypto from 'crypto';

/**
 * Setup tunnel routes
 */
export function setupTunnelRoutes(app: Express): void {
  app.post('/tunnel/create', (req: Request, res: Response) => {
    try {
      // Check API key authentication
      const providedApiKey =
        req.headers['x-api-key'] || req.headers['authorization']?.replace('Bearer ', '');

      const config = Config.get();

      if (!providedApiKey || providedApiKey !== config.registrationApiKey) {
        Logger.warn('Unauthorized tunnel registration attempt');
        throw new TunnelAuthError('Valid API key required for tunnel registration');
      }

      // Validate request body
      const validation = TunnelCreateRequestSchema.safeParse(req.body);
      if (!validation.success) {
        throw new InvalidRequestError(`Invalid request: ${validation.error.message}`);
      }

      const { name, tunnel_id } = validation.data;

      let tunnelId: string;
      let apiKey: string;
      let isRestored = false;

      if (tunnel_id) {
        // Restore existing tunnel
        tunnelId = tunnel_id;
        apiKey = crypto.randomBytes(32).toString('hex');
        isRestored = true;
        Logger.info('Restoring tunnel', { tunnelId, name });
      } else {
        // Create new tunnel
        tunnelId = crypto.randomBytes(8).toString('hex');
        apiKey = crypto.randomBytes(32).toString('hex');
        Logger.info('Creating new tunnel', { tunnelId, name });
      }

      const configResponse = {
        tunnelId,
        apiKey,
        publicUrl: `${config.baseUrl}/api/${tunnelId}`,
        wsUrl: `${config.wsProtocol}://${config.hostForUrl}/tunnel/${tunnelId}`,
        isRestored,
      };

      Logger.info('Tunnel created', {
        tunnelId,
        name: name || 'Unknown',
        isRestored,
        publicUrl: configResponse.publicUrl,
        wsUrl: configResponse.wsUrl,
      });

      res.json({ config: configResponse });
    } catch (error) {
      if (error instanceof TunnelAuthError || error instanceof InvalidRequestError) {
        res.status(error.statusCode).json({
          error: error.code,
          message: error.message,
        });
      } else {
        Logger.error('Error creating tunnel', {
          error: error instanceof Error ? error.message : 'Unknown error',
        });
        res.status(500).json({ error: 'Internal server error' });
      }
    }
  });
}
