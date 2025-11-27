/**
 * Custom error types for tunnel-server
 */

/**
 * Base tunnel error class
 */
export class TunnelError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly statusCode: number = 500
  ) {
    super(message);
    this.name = 'TunnelError';
    Error.captureStackTrace(this, this.constructor);
  }
}

/**
 * Tunnel not found error
 */
export class TunnelNotFoundError extends TunnelError {
  constructor(tunnelId: string) {
    super(`Tunnel not found: ${tunnelId}`, 'TUNNEL_NOT_FOUND', 404);
    this.name = 'TunnelNotFoundError';
  }
}

/**
 * Tunnel authentication error
 */
export class TunnelAuthError extends TunnelError {
  constructor(message: string = 'Unauthorized') {
    super(message, 'TUNNEL_AUTH_ERROR', 401);
    this.name = 'TunnelAuthError';
  }
}

/**
 * Tunnel connection error
 */
export class TunnelConnectionError extends TunnelError {
  constructor(message: string) {
    super(message, 'TUNNEL_CONNECTION_ERROR', 503);
    this.name = 'TunnelConnectionError';
  }
}

/**
 * Invalid request error
 */
export class InvalidRequestError extends TunnelError {
  constructor(message: string) {
    super(message, 'INVALID_REQUEST', 400);
    this.name = 'InvalidRequestError';
  }
}
