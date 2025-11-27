/**
 * Configuration management for tunnel-server
 * Handles environment variable loading and validation
 */

import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import { Logger } from '../utils/logger.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Tunnel server configuration
 */
export interface TunnelServerConfig {
  port: number;
  host: string;
  publicHost: string;
  publicProtocol: 'http' | 'https';
  registrationApiKey: string;
  nodeEnv: 'development' | 'production';
  pingIntervalMs: number;
  pongTimeoutMs: number;
  baseUrl: string;
  wsProtocol: 'ws' | 'wss';
  hostForUrl: string;
}

/**
 * Configuration manager
 */
export class Config {
  private static config: TunnelServerConfig | null = null;

  /**
   * Load and return configuration
   * Throws error if required environment variables are missing
   */
  static load(): TunnelServerConfig {
    if (this.config) {
      return this.config;
    }

    // Load .env files
    this.loadEnvFiles();

    // Validate required environment variables
    const registrationApiKey = process.env.TUNNEL_REGISTRATION_API_KEY;
    if (!registrationApiKey) {
      Logger.error('TUNNEL_REGISTRATION_API_KEY is not set in environment variables');
      Logger.error('Set it in tunnel-server/.env or pass as environment variable');
      throw new Error('TUNNEL_REGISTRATION_API_KEY is required');
    }

    // Parse configuration
    const port = parseInt(process.env.PORT || '8000', 10);
    const host = process.env.HOST || '0.0.0.0';
    const publicHost = process.env.PUBLIC_HOST || process.env.HOST || 'localhost';
    const publicProtocol = (process.env.PUBLIC_PROTOCOL || 'http') as 'http' | 'https';
    const wsProtocol = publicProtocol === 'https' ? 'wss' : 'ws';
    const nodeEnv = (process.env.NODE_ENV || 'development') as 'development' | 'production';

    // Determine host for URL construction
    let hostForUrl: string;
    if (publicHost.includes(':')) {
      hostForUrl = publicHost;
    } else if (publicProtocol === 'https') {
      hostForUrl = publicHost;
    } else {
      hostForUrl = port === 80 ? publicHost : `${publicHost}:${port}`;
    }

    const baseUrl = `${publicProtocol}://${hostForUrl}`;

    this.config = {
      port,
      host,
      publicHost,
      publicProtocol,
      registrationApiKey,
      nodeEnv,
      pingIntervalMs: 20000,
      pongTimeoutMs: 30000,
      baseUrl,
      wsProtocol,
      hostForUrl,
    };

    // Log configuration (without secrets)
    this.logConfiguration();

    return this.config;
  }

  /**
   * Load .env files in priority order:
   * 1. Service-specific .env (tunnel-server/.env) - highest priority
   * 2. Root .env (echoshell/.env) - fallback
   * 3. System environment variables (already loaded)
   */
  private static loadEnvFiles(): void {
    const serviceEnvPath = path.resolve(__dirname, '../../.env');
    const rootEnvPath = path.resolve(__dirname, '../../../.env');

    if (process.env.DOTENV_CONFIG_PATH) {
      // If explicitly set via environment variable, resolve it
      const explicitPath = path.isAbsolute(process.env.DOTENV_CONFIG_PATH)
        ? process.env.DOTENV_CONFIG_PATH
        : path.resolve(process.cwd(), process.env.DOTENV_CONFIG_PATH);
      dotenv.config({ path: explicitPath });
      Logger.debug('Loaded .env from DOTENV_CONFIG_PATH', { path: explicitPath });
    } else {
      // Otherwise, try service-specific, then root
      dotenv.config({ path: serviceEnvPath });
      dotenv.config({ path: rootEnvPath, override: false }); // Don't override service-specific values
      Logger.debug('Loaded .env files', {
        servicePath: serviceEnvPath,
        rootPath: rootEnvPath,
      });
    }
  }

  /**
   * Log configuration (sanitized)
   */
  private static logConfiguration(): void {
    const config = this.config!;
    Logger.info('Tunnel Server Configuration', {
      port: config.port,
      host: config.host,
      publicHost: config.publicHost,
      publicProtocol: config.publicProtocol,
      wsProtocol: config.wsProtocol,
      baseUrl: config.baseUrl,
      nodeEnv: config.nodeEnv,
      pingIntervalMs: config.pingIntervalMs,
      pongTimeoutMs: config.pongTimeoutMs,
    });

    // Warn if using localhost
    if (config.publicHost === 'localhost' || config.publicHost === '127.0.0.1') {
      Logger.warn('Using localhost as public host - only accessible locally', {
        publicHost: config.publicHost,
      });
    }
  }

  /**
   * Get current configuration (must call load() first)
   */
  static get(): TunnelServerConfig {
    if (!this.config) {
      throw new Error('Configuration not loaded. Call Config.load() first.');
    }
    return this.config;
  }
}
