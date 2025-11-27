/**
 * Zod validation schemas for tunnel-server
 */

import { z } from 'zod';

/**
 * Tunnel creation request schema
 */
export const TunnelCreateRequestSchema = z.object({
  name: z.string().optional(),
  tunnel_id: z.string().optional(),
});

export type TunnelCreateRequest = z.infer<typeof TunnelCreateRequestSchema>;

/**
 * WebSocket message base schema
 */
export const WebSocketMessageSchema = z.object({
  type: z.string(),
  requestId: z.string().optional(),
  statusCode: z.number().optional(),
  body: z.unknown().optional(),
});

export type WebSocketMessage = z.infer<typeof WebSocketMessageSchema>;

/**
 * HTTP response message schema
 */
export const HttpResponseMessageSchema = WebSocketMessageSchema.extend({
  type: z.literal('http_response'),
  requestId: z.string(),
  statusCode: z.number(),
  body: z.unknown(),
});

export type HttpResponseMessage = z.infer<typeof HttpResponseMessageSchema>;

/**
 * Client auth key message schema
 */
export const ClientAuthKeyMessageSchema = WebSocketMessageSchema.extend({
  type: z.literal('client_auth_key'),
  key: z.string().min(1),
});

export type ClientAuthKeyMessage = z.infer<typeof ClientAuthKeyMessageSchema>;

/**
 * Terminal output message schema
 */
export const TerminalOutputMessageSchema = WebSocketMessageSchema.extend({
  type: z.literal('terminal_output'),
  sessionId: z.string(),
  data: z.string(),
});

export type TerminalOutputMessage = z.infer<typeof TerminalOutputMessageSchema>;

/**
 * Recording output message schema
 */
export const RecordingOutputMessageSchema = WebSocketMessageSchema.extend({
  type: z.literal('recording_output'),
  sessionId: z.string(),
  text: z.string().optional(),
  delta: z.string().optional(),
  raw: z.unknown().optional(),
  timestamp: z.number().optional(),
  isComplete: z.boolean().optional(),
});

export type RecordingOutputMessage = z.infer<typeof RecordingOutputMessageSchema>;

/**
 * Terminal input message schema
 */
export const TerminalInputMessageSchema = z.object({
  type: z.literal('input'),
  data: z.string(),
});

export type TerminalInputMessage = z.infer<typeof TerminalInputMessageSchema>;

/**
 * HTTP request message schema
 */
export const HttpRequestMessageSchema = WebSocketMessageSchema.extend({
  type: z.literal('http_request'),
  requestId: z.string(),
  method: z.string(),
  path: z.string(),
  headers: z.record(z.string(), z.union([z.string(), z.array(z.string())]).optional()),
  body: z.unknown(),
  query: z.record(z.string(), z.string().optional()),
});

export type HttpRequestMessage = z.infer<typeof HttpRequestMessageSchema>;
