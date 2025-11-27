/**
 * Tests for TunnelError types
 */

import { describe, it, expect } from '@jest/globals';
import {
  TunnelError,
  TunnelNotFoundError,
  TunnelAuthError,
  TunnelConnectionError,
  InvalidRequestError,
} from '../TunnelError';

describe('TunnelError', () => {
  it('should create a base tunnel error', () => {
    const error = new TunnelError('Test error', 'TEST_ERROR', 400);
    expect(error).toBeInstanceOf(Error);
    expect(error).toBeInstanceOf(TunnelError);
    expect(error.message).toBe('Test error');
    expect(error.code).toBe('TEST_ERROR');
    expect(error.statusCode).toBe(400);
    expect(error.name).toBe('TunnelError');
  });

  it('should create a tunnel not found error', () => {
    const error = new TunnelNotFoundError('test-tunnel-id');
    expect(error).toBeInstanceOf(TunnelError);
    expect(error.message).toBe('Tunnel not found: test-tunnel-id');
    expect(error.code).toBe('TUNNEL_NOT_FOUND');
    expect(error.statusCode).toBe(404);
    expect(error.name).toBe('TunnelNotFoundError');
  });

  it('should create a tunnel auth error', () => {
    const error = new TunnelAuthError('Unauthorized');
    expect(error).toBeInstanceOf(TunnelError);
    expect(error.message).toBe('Unauthorized');
    expect(error.code).toBe('TUNNEL_AUTH_ERROR');
    expect(error.statusCode).toBe(401);
    expect(error.name).toBe('TunnelAuthError');
  });

  it('should create a tunnel auth error with default message', () => {
    const error = new TunnelAuthError();
    expect(error.message).toBe('Unauthorized');
    expect(error.code).toBe('TUNNEL_AUTH_ERROR');
    expect(error.statusCode).toBe(401);
  });

  it('should create a tunnel connection error', () => {
    const error = new TunnelConnectionError('Connection failed');
    expect(error).toBeInstanceOf(TunnelError);
    expect(error.message).toBe('Connection failed');
    expect(error.code).toBe('TUNNEL_CONNECTION_ERROR');
    expect(error.statusCode).toBe(503);
    expect(error.name).toBe('TunnelConnectionError');
  });

  it('should create an invalid request error', () => {
    const error = new InvalidRequestError('Invalid input');
    expect(error).toBeInstanceOf(TunnelError);
    expect(error.message).toBe('Invalid input');
    expect(error.code).toBe('INVALID_REQUEST');
    expect(error.statusCode).toBe(400);
    expect(error.name).toBe('InvalidRequestError');
  });
});
