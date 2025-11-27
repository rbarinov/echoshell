import express from 'express';
import { createServer, Server } from 'http';
import { WebSocketServer } from 'ws';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export interface ServerConfig {
  port: number;
  publicDir: string;
}

/**
 * Create Express app and HTTP server with WebSocket support
 */
export function createAppServer(config: ServerConfig): {
  app: express.Application;
  server: Server;
  wss: WebSocketServer;
} {
  const app = express();
  app.use(express.json());

  const server = createServer(app);
  const wss = new WebSocketServer({ server });

  // Serve static files
  app.use(express.static(config.publicDir));

  return { app, server, wss };
}

/**
 * Start HTTP server
 */
export function startServer(
  server: Server,
  port: number,
  host: string = '127.0.0.1'
): Promise<void> {
  return new Promise((resolve) => {
    server.listen(port, host, () => {
      console.log(`🌐 Server listening on http://${host}:${port}`);
      resolve();
    });
  });
}

/**
 * Middleware to restrict access to localhost only
 */
export function localhostOnly(
  req: express.Request,
  res: express.Response,
  next: express.NextFunction
): void {
  const clientIp = req.ip || req.socket.remoteAddress || '';
  const isLocalhost =
    clientIp === '127.0.0.1' ||
    clientIp === '::1' ||
    clientIp === '::ffff:127.0.0.1' ||
    req.hostname === 'localhost' ||
    req.hostname === '127.0.0.1';

  if (!isLocalhost) {
    res.status(403).json({
      error: 'Access denied. Web interface is only available on localhost.'
    });
    return;
  }

  next();
}
