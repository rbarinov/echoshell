/**
 * HTTP request proxying
 * Forwards HTTP requests from mobile devices to laptop via WebSocket
 */

import type { Express, Request, Response } from 'express';
import type { HttpRequestMessage } from '../types/index.js';
import { HttpRequestMessageSchema } from '../schemas/tunnelSchemas.js';
import { TunnelManager } from '../tunnel/TunnelManager.js';
import { TunnelNotFoundError, TunnelConnectionError } from '../errors/TunnelError.js';
import { Logger } from '../utils/logger.js';
import crypto from 'crypto';

/**
 * Manages HTTP request proxying to laptop
 */
export class HttpProxy {
  public readonly pendingRequests = new Map<string, Response>();
  private requestTimeoutMs = 30000; // 30 seconds

  constructor(private tunnelManager: TunnelManager) {}

  /**
   * Proxy HTTP request to laptop
   */
  async proxyRequest(req: Request, res: Response, tunnelId: string): Promise<void> {
    const tunnel = this.tunnelManager.get(tunnelId);

    if (!tunnel) {
      throw new TunnelNotFoundError(tunnelId);
    }

    if (tunnel.ws.readyState !== 1) {
      // WebSocket.OPEN = 1
      throw new TunnelConnectionError(`Tunnel ${tunnelId} is not connected`);
    }

    // Extract path after /api/:tunnelId/
    const fullPath = req.path;
    const prefix = `/api/${tunnelId}`;
    let path = fullPath.startsWith(prefix) ? fullPath.slice(prefix.length) : fullPath.replace(`/api/${tunnelId}`, '');

    // Normalize path
    if (!path || path === '') {
      path = '/';
    } else if (!path.startsWith('/')) {
      path = '/' + path;
    }
    path = path.replace(/\/+/g, '/');

    const requestId = crypto.randomBytes(8).toString('hex');

    Logger.debug('Proxying HTTP request', {
      tunnelId,
      method: req.method,
      originalPath: fullPath,
      proxiedPath: path,
      requestId,
    });

    // Store response handler
    this.pendingRequests.set(requestId, res);

    // Build request message
    const requestMessage: HttpRequestMessage = {
      type: 'http_request',
      requestId,
      method: req.method,
      path,
      headers: req.headers as Record<string, string | string[] | undefined>,
      body: req.body,
      query: req.query as Record<string, string | undefined>,
    };

    // Validate message
    const validation = HttpRequestMessageSchema.safeParse(requestMessage);
    if (!validation.success) {
      this.pendingRequests.delete(requestId);
      Logger.error('Invalid HTTP request message', { issues: validation.error.issues });
      res.status(500).json({ error: 'Invalid request format' });
      return;
    }

    // Forward request to laptop via WebSocket
    try {
      tunnel.ws.send(JSON.stringify(requestMessage));
    } catch (error) {
      this.pendingRequests.delete(requestId);
      Logger.error('Failed to send request to tunnel', {
        tunnelId,
        requestId,
        error: error instanceof Error ? error.message : 'Unknown error',
      });
      res.status(503).json({ error: 'Failed to forward request to laptop' });
      return;
    }

    // Set timeout
    setTimeout(() => {
      if (this.pendingRequests.has(requestId)) {
        this.pendingRequests.delete(requestId);
        Logger.warn('Request timeout', { tunnelId, requestId, timeout: this.requestTimeoutMs });
        res.status(504).json({ error: 'Gateway timeout' });
      }
    }, this.requestTimeoutMs);
  }

  /**
   * Get pending request by ID
   */
  getPendingRequest(requestId: string): Response | undefined {
    return this.pendingRequests.get(requestId);
  }

  /**
   * Delete pending request
   */
  deletePendingRequest(requestId: string): void {
    this.pendingRequests.delete(requestId);
  }
}
