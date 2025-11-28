/**
 * WebSocket server setup and connection routing
 */

import type { Server as HttpServer } from 'http';
import { WebSocketServer as WSServer, WebSocket, type RawData } from 'ws';
import type { TunnelConnection, StreamConnection } from '../types/index.js';
import { TunnelManager } from '../tunnel/TunnelManager.js';
import { StreamManager } from './handlers/streamManager.js';
import { TunnelHandler } from './handlers/tunnelHandler.js';
import { StreamHandler } from './handlers/streamHandler.js';
import { HeartbeatManager } from './heartbeat/HeartbeatManager.js';
import { Config } from '../config/Config.js';
import { Logger } from '../utils/logger.js';
import type { Response } from 'express';

/**
 * WebSocket server manager
 */
export class WebSocketServerManager {
  private wss: WSServer;
  private tunnelManager: TunnelManager;
  private streamManager: StreamManager;
  private tunnelHandler: TunnelHandler;
  private streamHandler: StreamHandler;
  private heartbeatManager: HeartbeatManager;

  constructor(
    server: HttpServer,
    tunnelManager: TunnelManager,
    streamManager: StreamManager,
    pendingRequests: Map<string, Response>
  ) {
    this.wss = new WSServer({ server });
    this.tunnelManager = tunnelManager;
    this.streamManager = streamManager;
    this.tunnelHandler = new TunnelHandler(tunnelManager, streamManager, pendingRequests);
    this.streamHandler = new StreamHandler(tunnelManager, streamManager);

    const config = Config.get();
    this.heartbeatManager = new HeartbeatManager({
      pingIntervalMs: config.pingIntervalMs,
      pongTimeoutMs: config.pongTimeoutMs,
    });

    this.setupConnectionHandling();
  }

  /**
   * Setup WebSocket connection handling
   */
  private setupConnectionHandling(): void {
    this.wss.on('connection', (ws: WebSocket, req) => {
      try {
        const url = new URL(req.url!, `http://${req.headers.host}`);
        const pathParts = url.pathname.split('/').filter((p) => p);

        // Route to appropriate handler based on path
        if (pathParts[0] === 'tunnel' && pathParts[1] && pathParts.length === 2) {
          this.handleTunnelConnection(ws, req, pathParts[1], url);
        } else if (
          pathParts[0] === 'api' &&
          pathParts[1] &&
          pathParts[2] === 'terminal' &&
          pathParts[3] &&
          pathParts[4] === 'stream'
        ) {
          this.handleTerminalStreamConnection(ws, pathParts[1], pathParts[3]);
        } else if (
          pathParts[0] === 'api' &&
          pathParts[1] &&
          pathParts[2] === 'recording' &&
          pathParts[3] &&
          pathParts[4] === 'stream'
        ) {
          this.handleRecordingStreamConnection(ws, pathParts[1], pathParts[3]);
        } else if (
          pathParts[0] === 'api' &&
          pathParts[1] &&
          pathParts[2] === 'agent' &&
          pathParts[3] === 'ws'
        ) {
          // Agent WebSocket - proxy to laptop's /agent/ws
          this.handleAgentStreamConnection(ws, pathParts[1]);
        } else {
          Logger.warn('Unknown WebSocket path', { path: url.pathname });
          ws.close(1008, 'Invalid WebSocket path');
        }
      } catch (error) {
        Logger.error('Error handling WebSocket connection', {
          error: error instanceof Error ? error.message : 'Unknown error',
        });
        ws.close(1011, 'Internal server error');
      }
    });
  }

  /**
   * Handle tunnel WebSocket connection (laptop connects here)
   */
  private handleTunnelConnection(
    ws: WebSocket,
    req: { url?: string; headers: { host?: string } },
    tunnelId: string,
    url: URL
  ): void {
    const apiKey = url.searchParams.get('api_key');

    if (!apiKey) {
      Logger.warn('Tunnel connection rejected: missing API key', { tunnelId });
      ws.close(1008, 'API key required');
      return;
    }

    // Register tunnel connection
    const tunnel = this.tunnelManager.register(tunnelId, apiKey, ws);
    Logger.info('Tunnel connected', { tunnelId });

    // Setup heartbeat
    this.heartbeatManager.setupTunnelHeartbeat(tunnel, (deadTunnelId) => {
      this.tunnelManager.delete(deadTunnelId);
    });

    // Handle messages from laptop
    ws.on('message', (data: RawData) => {
      let buffer: Buffer | string;
      if (Buffer.isBuffer(data)) {
        buffer = data;
      } else if (typeof data === 'string') {
        buffer = data;
      } else if (data instanceof ArrayBuffer) {
        buffer = Buffer.from(data);
      } else {
        // Array of Buffers - concatenate
        buffer = Buffer.concat(data as Buffer[]);
      }
      this.tunnelHandler.handleMessage(tunnelId, buffer);
    });

    // Handle pong
    ws.on('pong', () => {
      this.tunnelManager.updateLastPong(tunnelId);
    });

    // Handle disconnect
    ws.on('close', () => {
      Logger.info('Tunnel disconnected', { tunnelId });
      this.tunnelManager.cleanupIntervals(tunnelId);
      this.tunnelManager.delete(tunnelId);
    });

    // Send connection confirmation
    ws.send(JSON.stringify({ type: 'connected', tunnelId }));
  }

  /**
   * Handle terminal stream WebSocket connection (iPhone connects here)
   */
  private handleTerminalStreamConnection(ws: WebSocket, tunnelId: string, sessionId: string): void {
    const streamKey = `${tunnelId}:${sessionId}`;
    const connection: StreamConnection = {
      ws,
      lastPongReceived: Date.now(),
    };

    // Setup heartbeat
    this.heartbeatManager.setupStreamHeartbeat(
      streamKey,
      connection,
      this.streamManager.getTerminalStreamsMap(),
      (deadStreamKey, deadConnection) => {
        this.streamManager.unregisterTerminalStream(deadStreamKey, deadConnection);
      }
    );

    // Handle stream
    this.streamHandler.handleTerminalStream(tunnelId, sessionId, ws, streamKey, connection);

    // Handle pong
    ws.on('pong', () => {
      connection.lastPongReceived = Date.now();
    });

    // Handle disconnect cleanup
    ws.on('close', () => {
      this.heartbeatManager.cleanupStream(connection);
    });
  }

  /**
   * Handle recording stream WebSocket connection (iPhone connects here)
   */
  private handleRecordingStreamConnection(ws: WebSocket, tunnelId: string, sessionId: string): void {
    const streamKey = `${tunnelId}:${sessionId}:recording`;
    const connection: StreamConnection = {
      ws,
      lastPongReceived: Date.now(),
    };

    // Setup heartbeat
    this.heartbeatManager.setupStreamHeartbeat(
      streamKey,
      connection,
      this.streamManager.getRecordingWsStreamsMap(),
      (deadStreamKey, deadConnection) => {
        this.streamManager.unregisterRecordingWsStream(deadStreamKey, deadConnection);
      }
    );

    // Handle stream
    this.streamHandler.handleRecordingStream(streamKey, connection);

    // Handle pong
    ws.on('pong', () => {
      connection.lastPongReceived = Date.now();
    });

    // Handle disconnect cleanup
    ws.on('close', () => {
      this.heartbeatManager.cleanupStream(connection);
    });
  }

  /**
   * Handle agent WebSocket connection (iPhone connects here for agent mode)
   * Proxies messages between iPhone and laptop's /agent/ws
   */
  private handleAgentStreamConnection(ws: WebSocket, tunnelId: string): void {
    const streamKey = `${tunnelId}:agent`;
    Logger.info('Agent WebSocket connected', { tunnelId, streamKey });

    const connection: StreamConnection = {
      ws,
      lastPongReceived: Date.now(),
    };

    // Register agent connection
    this.streamManager.registerAgentStream(streamKey, connection);

    // Forward messages from iPhone to laptop
    ws.on('message', (data: RawData) => {
      try {
        const tunnel = this.tunnelManager.get(tunnelId);
        if (!tunnel || tunnel.ws.readyState !== WebSocket.OPEN) {
          Logger.warn('Tunnel not available for agent message', { tunnelId });
          ws.send(JSON.stringify({ type: 'error', error: 'Laptop not connected' }));
          return;
        }

        // Parse and validate message
        const message = JSON.parse(data.toString());
        
        // Forward to laptop with agent_request type
        tunnel.ws.send(JSON.stringify({
          type: 'agent_request',
          tunnelId,
          streamKey,
          payload: message
        }));

        Logger.debug('Agent message forwarded to laptop', { tunnelId, messageType: message.type });
      } catch (error) {
        Logger.error('Error processing agent message', {
          tunnelId,
          error: error instanceof Error ? error.message : 'Unknown error'
        });
        ws.send(JSON.stringify({ type: 'error', error: 'Invalid message format' }));
      }
    });

    // Handle pong
    ws.on('pong', () => {
      connection.lastPongReceived = Date.now();
    });

    // Handle disconnect
    ws.on('close', () => {
      Logger.info('Agent WebSocket disconnected', { tunnelId, streamKey });
      this.streamManager.unregisterAgentStream(streamKey, connection);
    });
  }
}
