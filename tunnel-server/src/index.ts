/**
 * Tunnel Server - Main Entry Point
 * Voice-Controlled Terminal Management System
 */

import { Config } from './config/Config';
import { Logger } from './utils/logger';
import { TunnelManager } from './tunnel/TunnelManager';
import { StreamManager } from './websocket/handlers/streamManager';
import { HttpProxy } from './proxy/HttpProxy';
import { createApp, createServer } from './server';
import { setupTunnelRoutes } from './routes/tunnel';
import { setupHealthRoutes } from './routes/health';
import { setupRecordingRoutes } from './routes/recording';
import { TunnelNotFoundError } from './errors/TunnelError';

import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, resolve } from 'path';

/**
 * Read version from package.json
 */
function getServerVersion(): string {
  try {
    const __filename = fileURLToPath(import.meta.url);
    const __dirname = dirname(__filename);
    const packageJsonPath = resolve(__dirname, '../package.json');
    const packageJson = JSON.parse(readFileSync(packageJsonPath, 'utf-8'));
    return packageJson.version || 'unknown';
  } catch (error) {
    Logger.warn('Could not read version from package.json', {
      error: error instanceof Error ? error.message : 'Unknown error',
    });
    return 'unknown';
  }
}

/**
 * Main function
 */
async function main(): Promise<void> {
  try {
    // Load configuration
    const config = Config.load();

    // Log startup
    const version = getServerVersion();
    Logger.info('Tunnel Server starting', { version });

    // Initialize managers
    const tunnelManager = new TunnelManager();
    const streamManager = new StreamManager();
    const httpProxy = new HttpProxy(tunnelManager);

    // Create Express app
    const app = createApp();

    // Setup routes
    setupTunnelRoutes(app);
    setupHealthRoutes(app, tunnelManager);
    setupRecordingRoutes(app, tunnelManager, streamManager);

    // Proxy HTTP requests to connected laptop
    app.all('/api/:tunnelId/*', async (req, res) => {
      try {
        const { tunnelId } = req.params;
        await httpProxy.proxyRequest(req, res, tunnelId);
      } catch (error) {
        if (error instanceof TunnelNotFoundError) {
          res.status(error.statusCode).json({
            error: error.code,
            message: error.message,
          });
        } else {
          Logger.error('Error proxying request', {
            error: error instanceof Error ? error.message : 'Unknown error',
          });
          res.status(500).json({ error: 'Internal server error' });
        }
      }
    });

    // Create HTTP server and WebSocket
    const { server } = createServer(app, tunnelManager, streamManager, httpProxy);

    // Start server
    server.listen(config.port, config.host, () => {
      Logger.info('Tunnel Server running', {
        port: config.port,
        host: config.host,
        baseUrl: config.baseUrl,
        wsProtocol: config.wsProtocol,
        pingIntervalMs: config.pingIntervalMs,
        pongTimeoutMs: config.pongTimeoutMs,
      });
    });

    // Graceful shutdown
    process.on('SIGTERM', () => {
      Logger.info('SIGTERM received, shutting down gracefully');
      server.close(() => {
        Logger.info('Server closed');
        process.exit(0);
      });
    });

    process.on('SIGINT', () => {
      Logger.info('SIGINT received, shutting down gracefully');
      server.close(() => {
        Logger.info('Server closed');
        process.exit(0);
      });
    });
  } catch (error) {
    Logger.error('Failed to start server', {
      error: error instanceof Error ? error.message : 'Unknown error',
      stack: error instanceof Error ? error.stack : undefined,
    });
    process.exit(1);
  }
}


// Start server
main().catch((error) => {
  Logger.error('Unhandled error in main', {
    error: error instanceof Error ? error.message : 'Unknown error',
    stack: error instanceof Error ? error.stack : undefined,
  });
  process.exit(1);
});
