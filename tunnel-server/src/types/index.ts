/**
 * Type definitions for tunnel-server
 */

import type { WebSocket } from 'ws';

/**
 * Tunnel connection representing a laptop connected via WebSocket
 */
export interface TunnelConnection {
  tunnelId: string;
  apiKey: string;
  name: string;
  ws: WebSocket;
  createdAt: number;
  clientAuthKey?: string;
  lastPongReceived: number;
  pingInterval?: NodeJS.Timeout;
  healthCheckInterval?: NodeJS.Timeout;
}

/**
 * Stream connection representing a client (iPhone) connected to a stream
 */
export interface StreamConnection {
  ws: WebSocket;
  lastPongReceived: number;
  pingInterval?: NodeJS.Timeout;
  healthCheckInterval?: NodeJS.Timeout;
}

/**
 * WebSocket message types
 */
export interface WebSocketMessage {
  type: string;
  requestId?: string;
  statusCode?: number;
  body?: unknown;
}

/**
 * HTTP response message from laptop
 */
export interface HttpResponseMessage extends WebSocketMessage {
  type: 'http_response';
  requestId: string;
  statusCode: number;
  body: unknown;
}

/**
 * Client auth key registration message
 */
export interface ClientAuthKeyMessage extends WebSocketMessage {
  type: 'client_auth_key';
  key: string;
}

/**
 * Terminal output message from laptop
 */
export interface TerminalOutputMessage extends WebSocketMessage {
  type: 'terminal_output';
  sessionId: string;
  data: string;
}

/**
 * Recording output message from laptop
 */
export interface RecordingOutputMessage extends WebSocketMessage {
  type: 'recording_output';
  sessionId: string;
  text?: string;
  delta?: string;
  raw?: unknown;
  timestamp?: number;
  isComplete?: boolean;
}

/**
 * Terminal input message from client
 */
export interface TerminalInputMessage {
  type: 'input';
  data: string;
}

/**
 * HTTP request message to laptop
 */
export interface HttpRequestMessage extends WebSocketMessage {
  type: 'http_request';
  requestId: string;
  method: string;
  path: string;
  headers: Record<string, string | string[] | undefined>;
  body: unknown;
  query: Record<string, string | undefined>;
}

/**
 * Tunnel creation request
 */
export interface TunnelCreateRequest {
  name?: string;
  tunnel_id?: string;
}

/**
 * Tunnel configuration response
 */
export interface TunnelConfig {
  tunnelId: string;
  apiKey: string;
  publicUrl: string;
  wsUrl: string;
  isRestored?: boolean;
}
