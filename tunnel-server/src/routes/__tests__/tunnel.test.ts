/**
 * Tests for tunnel routes
 */

import { describe, it, expect, beforeEach, afterEach } from '@jest/globals';
import express, { type Express } from 'express';
import request from 'supertest';
import { setupTunnelRoutes } from '../tunnel';
import { Config } from '../../config/Config';

describe('Tunnel Routes', () => {
  let app: Express;
  const originalEnv = process.env;

  beforeEach(() => {
    app = express();
    app.use(express.json());
    setupTunnelRoutes(app);
    
    // Setup minimal config
    process.env = { ...originalEnv };
    process.env.TUNNEL_REGISTRATION_API_KEY = 'test-api-key';
    (Config as any).config = {
      registrationApiKey: 'test-api-key',
      baseUrl: 'http://localhost:8000',
      wsProtocol: 'ws',
      hostForUrl: 'localhost:8000',
    };
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  it('should create a new tunnel with valid API key', async () => {
    const response = await request(app)
      .post('/tunnel/create')
      .set('X-API-Key', 'test-api-key')
      .send({ name: 'Test Laptop' });

    expect(response.status).toBe(200);
    expect(response.body.config).toBeDefined();
    expect(response.body.config.tunnelId).toBeDefined();
    expect(typeof response.body.config.tunnelId).toBe('string');
    expect(response.body.config.apiKey).toBeDefined();
    expect(typeof response.body.config.apiKey).toBe('string');
    expect(response.body.config.publicUrl).toContain('/api/');
    expect(response.body.config.wsUrl).toContain('/tunnel/');
    expect(response.body.config.isRestored).toBe(false);
  });

  it('should reject request without API key', async () => {
    const response = await request(app)
      .post('/tunnel/create')
      .send({ name: 'Test Laptop' });

    expect(response.status).toBe(401);
    expect(response.body.error).toBe('TUNNEL_AUTH_ERROR');
  });

  it('should reject request with invalid API key', async () => {
    const response = await request(app)
      .post('/tunnel/create')
      .set('X-API-Key', 'wrong-key')
      .send({ name: 'Test Laptop' });

    expect(response.status).toBe(401);
    expect(response.body.error).toBe('TUNNEL_AUTH_ERROR');
  });

  it('should restore tunnel with tunnel_id', async () => {
    const response = await request(app)
      .post('/tunnel/create')
      .set('X-API-Key', 'test-api-key')
      .send({ tunnel_id: 'existing-tunnel-123' });

    expect(response.status).toBe(200);
    expect(response.body.config.tunnelId).toBe('existing-tunnel-123');
    expect(response.body.config.isRestored).toBe(true);
  });

  it('should reject invalid request body', async () => {
    const response = await request(app)
      .post('/tunnel/create')
      .set('X-API-Key', 'test-api-key')
      .send({ name: 123 }); // Invalid type

    expect(response.status).toBe(400);
    expect(response.body.error).toBe('INVALID_REQUEST');
  });
});
