/**
 * Tests for TunnelManager
 */

import { describe, it, expect, beforeEach } from '@jest/globals';
import { TunnelManager } from '../TunnelManager';
import { WebSocket } from 'ws';

describe('TunnelManager', () => {
  let manager: TunnelManager;
  let mockWs: WebSocket;

  beforeEach(() => {
    manager = new TunnelManager();
    // Create a mock WebSocket
    mockWs = {
      readyState: 1, // OPEN
    } as unknown as WebSocket;
  });

  it('should register a tunnel', () => {
    const connection = manager.register('tunnel-1', 'api-key-1', mockWs, 'Test Laptop');
    expect(connection.tunnelId).toBe('tunnel-1');
    expect(connection.apiKey).toBe('api-key-1');
    expect(connection.name).toBe('Test Laptop');
    expect(connection.ws).toBe(mockWs);
    expect(connection.createdAt).toBeGreaterThan(0);
  });

  it('should get a registered tunnel', () => {
    manager.register('tunnel-1', 'api-key-1', mockWs);
    const tunnel = manager.get('tunnel-1');
    expect(tunnel).toBeDefined();
    expect(tunnel?.tunnelId).toBe('tunnel-1');
  });

  it('should return undefined for non-existent tunnel', () => {
    const tunnel = manager.get('non-existent');
    expect(tunnel).toBeUndefined();
  });

  it('should check if tunnel exists', () => {
    manager.register('tunnel-1', 'api-key-1', mockWs);
    expect(manager.has('tunnel-1')).toBe(true);
    expect(manager.has('non-existent')).toBe(false);
  });

  it('should delete a tunnel', () => {
    manager.register('tunnel-1', 'api-key-1', mockWs);
    expect(manager.has('tunnel-1')).toBe(true);
    manager.delete('tunnel-1');
    expect(manager.has('tunnel-1')).toBe(false);
  });

  it('should get all tunnels', () => {
    manager.register('tunnel-1', 'api-key-1', mockWs);
    manager.register('tunnel-2', 'api-key-2', mockWs);
    const all = manager.getAll();
    expect(all.length).toBe(2);
    expect(all.map((t) => t.tunnelId)).toContain('tunnel-1');
    expect(all.map((t) => t.tunnelId)).toContain('tunnel-2');
  });

  it('should return correct size', () => {
    expect(manager.size()).toBe(0);
    manager.register('tunnel-1', 'api-key-1', mockWs);
    expect(manager.size()).toBe(1);
    manager.register('tunnel-2', 'api-key-2', mockWs);
    expect(manager.size()).toBe(2);
  });

  it('should set client auth key', () => {
    manager.register('tunnel-1', 'api-key-1', mockWs);
    manager.setClientAuthKey('tunnel-1', 'client-key-123');
    const tunnel = manager.get('tunnel-1');
    expect(tunnel?.clientAuthKey).toBe('client-key-123');
  });

  it('should update last pong timestamp', () => {
    manager.register('tunnel-1', 'api-key-1', mockWs);
    const tunnel = manager.get('tunnel-1');
    const initialPong = tunnel!.lastPongReceived;
    
    // Update pong
    manager.updateLastPong('tunnel-1');
    const updatedTunnel = manager.get('tunnel-1');
    expect(updatedTunnel!.lastPongReceived).toBeGreaterThanOrEqual(initialPong);
  });

  it('should cleanup intervals', () => {
    manager.register('tunnel-1', 'api-key-1', mockWs);
    const tunnel = manager.get('tunnel-1');
    
    // Set mock intervals
    tunnel!.pingInterval = setInterval(() => {}, 1000) as unknown as NodeJS.Timeout;
    tunnel!.healthCheckInterval = setInterval(() => {}, 1000) as unknown as NodeJS.Timeout;
    
    manager.cleanupIntervals('tunnel-1');
    const updatedTunnel = manager.get('tunnel-1');
    expect(updatedTunnel?.pingInterval).toBeUndefined();
    expect(updatedTunnel?.healthCheckInterval).toBeUndefined();
  });
});
