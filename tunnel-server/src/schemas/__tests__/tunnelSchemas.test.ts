/**
 * Tests for tunnel schemas
 */

import { describe, it, expect } from '@jest/globals';
import {
  TunnelCreateRequestSchema,
  HttpResponseMessageSchema,
  ClientAuthKeyMessageSchema,
  TerminalOutputMessageSchema,
  RecordingOutputMessageSchema,
  TerminalInputMessageSchema,
  HttpRequestMessageSchema,
} from '../tunnelSchemas';

describe('TunnelCreateRequestSchema', () => {
  it('should validate valid request with name', () => {
    const result = TunnelCreateRequestSchema.safeParse({ name: 'My Laptop' });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.name).toBe('My Laptop');
    }
  });

  it('should validate valid request with tunnel_id', () => {
    const result = TunnelCreateRequestSchema.safeParse({ tunnel_id: 'tunnel-123' });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.tunnel_id).toBe('tunnel-123');
    }
  });

  it('should validate empty request', () => {
    const result = TunnelCreateRequestSchema.safeParse({});
    expect(result.success).toBe(true);
  });

  it('should reject invalid types', () => {
    const result = TunnelCreateRequestSchema.safeParse({ name: 123 });
    expect(result.success).toBe(false);
  });
});

describe('HttpResponseMessageSchema', () => {
  it('should validate valid HTTP response', () => {
    const result = HttpResponseMessageSchema.safeParse({
      type: 'http_response',
      requestId: 'req-123',
      statusCode: 200,
      body: { data: 'test' },
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.type).toBe('http_response');
      expect(result.data.requestId).toBe('req-123');
      expect(result.data.statusCode).toBe(200);
    }
  });

  it('should reject missing required fields', () => {
    const result = HttpResponseMessageSchema.safeParse({
      type: 'http_response',
      requestId: 'req-123',
    });
    expect(result.success).toBe(false);
  });
});

describe('ClientAuthKeyMessageSchema', () => {
  it('should validate valid client auth key message', () => {
    const result = ClientAuthKeyMessageSchema.safeParse({
      type: 'client_auth_key',
      key: 'auth-key-123',
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.key).toBe('auth-key-123');
    }
  });

  it('should reject empty key', () => {
    const result = ClientAuthKeyMessageSchema.safeParse({
      type: 'client_auth_key',
      key: '',
    });
    expect(result.success).toBe(false);
  });
});

describe('TerminalOutputMessageSchema', () => {
  it('should validate valid terminal output', () => {
    const result = TerminalOutputMessageSchema.safeParse({
      type: 'terminal_output',
      sessionId: 'session-123',
      data: 'output text',
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.sessionId).toBe('session-123');
      expect(result.data.data).toBe('output text');
    }
  });
});

describe('RecordingOutputMessageSchema', () => {
  it('should validate valid recording output', () => {
    const result = RecordingOutputMessageSchema.safeParse({
      type: 'recording_output',
      sessionId: 'session-123',
      text: 'recorded text',
      isComplete: true,
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.sessionId).toBe('session-123');
      expect(result.data.text).toBe('recorded text');
      expect(result.data.isComplete).toBe(true);
    }
  });

  it('should validate recording output without optional fields', () => {
    const result = RecordingOutputMessageSchema.safeParse({
      type: 'recording_output',
      sessionId: 'session-123',
    });
    expect(result.success).toBe(true);
  });
});

describe('TerminalInputMessageSchema', () => {
  it('should validate valid terminal input', () => {
    const result = TerminalInputMessageSchema.safeParse({
      type: 'input',
      data: 'input text',
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.type).toBe('input');
      expect(result.data.data).toBe('input text');
    }
  });
});

describe('HttpRequestMessageSchema', () => {
  it('should validate valid HTTP request', () => {
    const result = HttpRequestMessageSchema.safeParse({
      type: 'http_request',
      requestId: 'req-123',
      method: 'POST',
      path: '/api/test',
      headers: { 'Content-Type': 'application/json' },
      body: { data: 'test' },
      query: { param: 'value' },
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.method).toBe('POST');
      expect(result.data.path).toBe('/api/test');
    }
  });

  it('should reject missing required fields', () => {
    const result = HttpRequestMessageSchema.safeParse({
      type: 'http_request',
      requestId: 'req-123',
    });
    expect(result.success).toBe(false);
  });
});
