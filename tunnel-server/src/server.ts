/**
 * Express server setup
 */

import express, { type Express as ExpressType } from 'express';
import cors from 'cors';
import http, { type Server as HttpServer } from 'http';
import { TunnelManager } from './tunnel/TunnelManager.js';
import { StreamManager } from './websocket/handlers/streamManager.js';
import { HttpProxy } from './proxy/HttpProxy.js';
import { WebSocketServerManager } from './websocket/WebSocketServer.js';

/**
 * Create and configure Express app
 */
export function createApp(): ExpressType {
  const app = express();

  // Middleware
  app.use(cors());
  app.use(express.json());

  return app;
}

/**
 * Create HTTP server and setup WebSocket
 */
export function createServer(
  app: ExpressType,
  tunnelManager: TunnelManager,
  streamManager: StreamManager,
  httpProxy: HttpProxy
): { server: HttpServer; wsManager: WebSocketServerManager } {
  const server = http.createServer(app);

  const wsManager = new WebSocketServerManager(
    server,
    tunnelManager,
    streamManager,
    httpProxy.pendingRequests
  );

  return { server, wsManager };
}
