/**
 * Common types for tunnel requests and responses
 */

export interface TunnelRequest {
  method: string;
  path: string;
  body: unknown;
  query: Record<string, string | undefined>;
  headers: Record<string, string | string[] | undefined>;
  requestId: string;
}

export interface TunnelResponse {
  statusCode: number;
  body: unknown;
}
