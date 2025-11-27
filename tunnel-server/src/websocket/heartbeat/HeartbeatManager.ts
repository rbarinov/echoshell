/**
 * Heartbeat management for WebSocket connections
 * Handles ping/pong and dead connection detection
 */

import { WebSocket } from 'ws';
import type { TunnelConnection, StreamConnection } from '../../types/index.js';
import { Logger } from '../../utils/logger.js';

/**
 * Heartbeat configuration
 */
interface HeartbeatConfig {
  pingIntervalMs: number;
  pongTimeoutMs: number;
}

/**
 * Manages heartbeat for WebSocket connections
 */
export class HeartbeatManager {
  private config: HeartbeatConfig;

  constructor(config: HeartbeatConfig) {
    this.config = config;
  }

  /**
   * Setup heartbeat for tunnel connection
   */
  setupTunnelHeartbeat(
    tunnel: TunnelConnection,
    onDeadConnection: (tunnelId: string) => void
  ): void {
    // Send periodic pings
    tunnel.pingInterval = setInterval(() => {
      if (tunnel.ws.readyState === WebSocket.OPEN) {
        tunnel.ws.ping();
      }
    }, this.config.pingIntervalMs);

    // Check for dead connections
    tunnel.healthCheckInterval = setInterval(() => {
      const timeSinceLastPong = Date.now() - tunnel.lastPongReceived;
      if (timeSinceLastPong > this.config.pongTimeoutMs) {
        Logger.warn('Tunnel appears dead, closing connection', {
          tunnelId: tunnel.tunnelId,
          timeSinceLastPong,
        });
        this.cleanupTunnel(tunnel);
        onDeadConnection(tunnel.tunnelId);
      }
    }, this.config.pongTimeoutMs);
  }

  /**
   * Setup heartbeat for stream connection
   */
  setupStreamHeartbeat(
    streamKey: string,
    connection: StreamConnection,
    streamMap: Map<string, Set<StreamConnection>>,
    onDeadConnection: (streamKey: string, connection: StreamConnection) => void
  ): void {
    // Send periodic pings
    connection.pingInterval = setInterval(() => {
      if (connection.ws.readyState === WebSocket.OPEN) {
        connection.ws.ping();
      }
    }, this.config.pingIntervalMs);

    // Check for dead connections
    connection.healthCheckInterval = setInterval(() => {
      const connections = streamMap.get(streamKey);
      if (!connections || !connections.has(connection)) {
        this.cleanupStream(connection);
        return;
      }

      const timeSinceLastPong = Date.now() - connection.lastPongReceived;
      if (timeSinceLastPong > this.config.pongTimeoutMs) {
        Logger.warn('Stream appears dead, closing connection', {
          streamKey,
          timeSinceLastPong,
        });
        this.cleanupStream(connection);
        onDeadConnection(streamKey, connection);
      }
    }, this.config.pongTimeoutMs);
  }

  /**
   * Cleanup tunnel heartbeat intervals
   */
  cleanupTunnel(tunnel: TunnelConnection): void {
    if (tunnel.pingInterval) {
      clearInterval(tunnel.pingInterval);
      tunnel.pingInterval = undefined;
    }
    if (tunnel.healthCheckInterval) {
      clearInterval(tunnel.healthCheckInterval);
      tunnel.healthCheckInterval = undefined;
    }
    if (tunnel.ws.readyState === WebSocket.OPEN) {
      tunnel.ws.terminate();
    }
  }

  /**
   * Cleanup stream heartbeat intervals
   */
  cleanupStream(connection: StreamConnection): void {
    if (connection.pingInterval) {
      clearInterval(connection.pingInterval);
      connection.pingInterval = undefined;
    }
    if (connection.healthCheckInterval) {
      clearInterval(connection.healthCheckInterval);
      connection.healthCheckInterval = undefined;
    }
    if (connection.ws.readyState === WebSocket.OPEN) {
      connection.ws.terminate();
    }
  }
}
