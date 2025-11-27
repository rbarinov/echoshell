import type { KeyManager } from '../keys/KeyManager';
import type { TunnelRequest, TunnelResponse } from '../types';
import type { TunnelConfig } from '../tunnel/TunnelClient';
import {
  RequestKeysRequestSchema,
  RefreshKeysRequestSchema,
  RevokeKeysQuerySchema
} from '../schemas/keySchemas';
import { validateRequest, validateQuery } from '../utils/validation';
import logger from '../utils/logger';

export class KeyHandler {
  constructor(
    private keyManager: KeyManager,
    private tunnelConfig: TunnelConfig | null
  ) {}

  setTunnelConfig(tunnelConfig: TunnelConfig | null): void {
    (this as any).tunnelConfig = tunnelConfig;
  }

  handleRequest(req: TunnelRequest): TunnelResponse {
    const { method, path, body, query } = req;

    if (path === '/keys/request' && method === 'POST') {
      return this.handleRequestKeys(body);
    }

    if (path === '/keys/refresh' && method === 'POST') {
      return this.handleRefreshKeys(body);
    }

    if (path === '/keys/revoke' && method === 'DELETE') {
      return this.handleRevokeKeys(query);
    }

    return { statusCode: 404, body: { error: 'Not found' } };
  }

  private handleRequestKeys(body: unknown): TunnelResponse {
    const validation = validateRequest(RequestKeysRequestSchema, body);
    if (!validation.success) {
      return validation.response;
    }

    const { device_id, duration_seconds, permissions } = validation.data;

    const keys = this.keyManager.issueEphemeralKeys(
      device_id,
      duration_seconds || 3600,
      permissions || ['stt', 'tts']
    );

    logger.info('Issued ephemeral keys', { deviceId: device_id });

    return {
      statusCode: 200,
      body: {
        status: 'success',
        keys: {
          stt: keys.sttKey,
          tts: keys.ttsKey
        },
        providers: {
          stt: keys.sttProvider,
          tts: keys.ttsProvider
        },
        endpoints: {
          stt: this.tunnelConfig
            ? `${this.tunnelConfig.publicUrl}/proxy/stt/transcribe`
            : keys.sttEndpoint,
          tts: this.tunnelConfig
            ? `${this.tunnelConfig.publicUrl}/proxy/tts/synthesize`
            : keys.ttsEndpoint
        },
        config: {
          stt: {
            baseUrl: keys.sttBaseUrl,
            model: keys.sttModel
          },
          tts: {
            baseUrl: keys.ttsBaseUrl,
            model: keys.ttsModel,
            voice: keys.ttsVoice
          }
        },
        expires_at: keys.expiresAt,
        expires_in: keys.expiresIn,
        permissions: keys.permissions
      }
    };
  }

  private handleRefreshKeys(body: unknown): TunnelResponse {
    const validation = validateRequest(RefreshKeysRequestSchema, body);
    if (!validation.success) {
      return validation.response;
    }

    const { device_id } = validation.data;

    const keys = this.keyManager.refreshKeys(device_id);

    if (keys) {
      logger.info('Refreshed keys', { deviceId: device_id });
      return {
        statusCode: 200,
        body: {
          status: 'refreshed',
          expires_at: keys.expiresAt,
          expires_in: keys.expiresIn
        }
      };
    }

    return { statusCode: 404, body: { error: 'Keys not found' } };
  }

  private handleRevokeKeys(query: Record<string, string | undefined>): TunnelResponse {
    const validation = validateQuery(RevokeKeysQuerySchema, query);
    if (!validation.success) {
      return validation.response;
    }

    const { device_id } = validation.data;

    this.keyManager.revokeKeys(device_id);

    logger.info('Revoked keys', { deviceId: device_id });

    return { statusCode: 200, body: { status: 'revoked' } };
  }
}
