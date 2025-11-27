/**
 * Tests for Config
 */

import { describe, it, expect, beforeEach, afterEach } from '@jest/globals';
import { Config } from '../Config';

describe('Config', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    // Reset process.env
    process.env = { ...originalEnv };
    // Clear Config singleton
    (Config as any).config = null;
  });

  afterEach(() => {
    process.env = originalEnv;
    (Config as any).config = null;
  });

  it('should load configuration with required environment variables', () => {
    process.env.TUNNEL_REGISTRATION_API_KEY = 'test-api-key';
    process.env.PORT = '9000';
    process.env.HOST = '127.0.0.1';
    process.env.PUBLIC_HOST = 'example.com';
    process.env.PUBLIC_PROTOCOL = 'https';

    const config = Config.load();
    expect(config.registrationApiKey).toBe('test-api-key');
    expect(config.port).toBe(9000);
    expect(config.host).toBe('127.0.0.1');
    expect(config.publicHost).toBe('example.com');
    expect(config.publicProtocol).toBe('https');
    expect(config.wsProtocol).toBe('wss');
  });

  it('should use default values when environment variables are not set', () => {
    // Clear all env vars that might affect config
    delete process.env.PORT;
    delete process.env.HOST;
    delete process.env.PUBLIC_HOST;
    delete process.env.PUBLIC_PROTOCOL;
    process.env.TUNNEL_REGISTRATION_API_KEY = 'test-api-key';

    const config = Config.load();
    expect(config.port).toBe(8000);
    expect(config.host).toBe('0.0.0.0');
    // Note: publicHost might come from .env file, so we just check it's defined
    expect(config.publicHost).toBeDefined();
    expect(config.publicProtocol).toBe('http');
    expect(config.wsProtocol).toBe('ws');
  });

  it('should throw error when TUNNEL_REGISTRATION_API_KEY is missing', () => {
    // Clear config singleton to force reload
    (Config as any).config = null;
    delete process.env.TUNNEL_REGISTRATION_API_KEY;
    
    // Mock dotenv to not load from file
    const originalDotenv = process.env.DOTENV_CONFIG_PATH;
    process.env.DOTENV_CONFIG_PATH = '/nonexistent/path/.env';
    
    try {
      expect(() => Config.load()).toThrow('TUNNEL_REGISTRATION_API_KEY is required');
    } finally {
      if (originalDotenv) {
        process.env.DOTENV_CONFIG_PATH = originalDotenv;
      } else {
        delete process.env.DOTENV_CONFIG_PATH;
      }
      (Config as any).config = null;
    }
  });

  it('should construct baseUrl correctly', () => {
    process.env.TUNNEL_REGISTRATION_API_KEY = 'test-api-key';
    process.env.PUBLIC_HOST = 'example.com';
    process.env.PUBLIC_PROTOCOL = 'https';
    process.env.PORT = '443';

    const config = Config.load();
    expect(config.baseUrl).toBe('https://example.com');
  });

  it('should include port in baseUrl for non-standard ports', () => {
    process.env.TUNNEL_REGISTRATION_API_KEY = 'test-api-key';
    process.env.PUBLIC_HOST = 'example.com';
    process.env.PORT = '8080';

    const config = Config.load();
    expect(config.baseUrl).toBe('http://example.com:8080');
  });

  it('should return same config instance on multiple calls', () => {
    process.env.TUNNEL_REGISTRATION_API_KEY = 'test-api-key';
    const config1 = Config.load();
    const config2 = Config.load();
    expect(config1).toBe(config2);
  });

  it('should throw error when get() is called before load()', () => {
    (Config as any).config = null;
    expect(() => Config.get()).toThrow('Configuration not loaded');
  });
});
