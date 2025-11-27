/**
 * Tunnel connection management
 * Handles registration, lookup, and cleanup of tunnel connections
 */

import type { WebSocket } from 'ws';
import type { TunnelConnection } from '../types';
import { Logger } from '../utils/logger';

/**
 * Manages tunnel connections
 */
export class TunnelManager {
  private tunnels = new Map<string, TunnelConnection>();

  /**
   * Register a new tunnel connection
   */
  register(tunnelId: string, apiKey: string, ws: WebSocket, name: string = 'Laptop'): TunnelConnection {
    const connection: TunnelConnection = {
      tunnelId,
      apiKey,
      name,
      ws,
      createdAt: Date.now(),
      lastPongReceived: Date.now(),
    };

    this.tunnels.set(tunnelId, connection);
    Logger.info('Tunnel registered', { tunnelId, name });
    return connection;
  }

  /**
   * Get tunnel connection by ID
   */
  get(tunnelId: string): TunnelConnection | undefined {
    return this.tunnels.get(tunnelId);
  }

  /**
   * Check if tunnel exists
   */
  has(tunnelId: string): boolean {
    return this.tunnels.has(tunnelId);
  }

  /**
   * Delete tunnel connection
   */
  delete(tunnelId: string): void {
    const tunnel = this.tunnels.get(tunnelId);
    if (tunnel) {
      this.tunnels.delete(tunnelId);
      Logger.info('Tunnel deleted', { tunnelId });
    }
  }

  /**
   * Get all tunnel connections
   */
  getAll(): TunnelConnection[] {
    return Array.from(this.tunnels.values());
  }

  /**
   * Get number of active tunnels
   */
  size(): number {
    return this.tunnels.size;
  }

  /**
   * Update tunnel's client auth key
   */
  setClientAuthKey(tunnelId: string, clientAuthKey: string): void {
    const tunnel = this.tunnels.get(tunnelId);
    if (tunnel) {
      tunnel.clientAuthKey = clientAuthKey;
      Logger.info('Client auth key set for tunnel', { tunnelId });
    }
  }

  /**
   * Update tunnel's last pong received timestamp
   */
  updateLastPong(tunnelId: string): void {
    const tunnel = this.tunnels.get(tunnelId);
    if (tunnel) {
      tunnel.lastPongReceived = Date.now();
    }
  }

  /**
   * Clean up intervals for a tunnel
   */
  cleanupIntervals(tunnelId: string): void {
    const tunnel = this.tunnels.get(tunnelId);
    if (tunnel) {
      if (tunnel.pingInterval) {
        clearInterval(tunnel.pingInterval);
        tunnel.pingInterval = undefined;
      }
      if (tunnel.healthCheckInterval) {
        clearInterval(tunnel.healthCheckInterval);
        tunnel.healthCheckInterval = undefined;
      }
    }
  }
}
