/**
 * Health check routes
 */

import type { Express, Request, Response } from 'express';
import { TunnelManager } from '../tunnel/TunnelManager.js';

/**
 * Setup health check routes
 */
export function setupHealthRoutes(app: Express, tunnelManager: TunnelManager): void {
  app.get('/health', (req: Request, res: Response) => {
    res.json({
      status: 'ok',
      tunnels: tunnelManager.size(),
      uptime: process.uptime(),
    });
  });
}
