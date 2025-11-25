import type { STTProvider } from './STTProvider.js';
import type { TTSProvider } from './TTSProvider.js';

interface EphemeralKey {
  deviceId: string;
  sttKey: string;
  ttsKey: string;
  sttProvider: string;
  ttsProvider: string;
  expiresAt: number;
  issuedAt: number;
  permissions: string[];
}

interface UsageLogEntry {
  type: 'issue' | 'refresh' | 'revoke';
  deviceId: string;
  timestamp: number;
  expiresAt?: number;
  permissions?: string[];
}

export class KeyManager {
  private keys = new Map<string, EphemeralKey>();
  private usageLog: UsageLogEntry[] = [];
  
  constructor(
    private sttProvider: STTProvider,
    private ttsProvider: TTSProvider
  ) {}
  
  issueEphemeralKeys(deviceId: string, durationSeconds: number, permissions: string[]): {
    sttKey: string;
    ttsKey: string;
    sttProvider: string;
    ttsProvider: string;
    sttEndpoint: string;
    ttsEndpoint: string;
    sttBaseUrl: string | undefined;
    ttsBaseUrl: string | undefined;
    sttModel: string;
    ttsModel: string;
    ttsVoice: string;
    expiresAt: number;
    expiresIn: number;
    permissions: string[];
  } {
    const now = Date.now();
    const expiresAt = now + (durationSeconds * 1000);
    
    // For now, we'll use the master keys as ephemeral keys
    // In production, you'd want to create actual ephemeral keys via API
    const ephemeralKey: EphemeralKey = {
      deviceId,
      sttKey: this.sttProvider.getApiKey(),
      ttsKey: this.ttsProvider.getApiKey(),
      sttProvider: this.sttProvider.getProviderType(),
      ttsProvider: this.ttsProvider.getProviderType(),
      expiresAt,
      issuedAt: now,
      permissions
    };
    
    this.keys.set(deviceId, ephemeralKey);
    
    // Log usage
    this.usageLog.push({
      type: 'issue',
      deviceId,
      timestamp: now,
      expiresAt,
      permissions
    });
    
    return {
      sttKey: ephemeralKey.sttKey,
      ttsKey: ephemeralKey.ttsKey,
      sttProvider: ephemeralKey.sttProvider,
      ttsProvider: ephemeralKey.ttsProvider,
      sttEndpoint: this.sttProvider.getEndpoint(),
      ttsEndpoint: this.ttsProvider.getEndpoint(),
      sttBaseUrl: this.sttProvider.getBaseUrl(),
      ttsBaseUrl: this.ttsProvider.getBaseUrl(),
      sttModel: this.sttProvider.getModel(),
      ttsModel: this.ttsProvider.getModel(),
      ttsVoice: this.ttsProvider.getVoice(),
      expiresAt: Math.floor(expiresAt / 1000),
      expiresIn: durationSeconds,
      permissions
    };
  }
  
  refreshKeys(deviceId: string): {
    expiresAt: number;
    expiresIn: number;
  } | null {
    const key = this.keys.get(deviceId);
    
    if (!key) {
      return null;
    }
    
    const now = Date.now();
    const expiresAt = now + 3600000; // 1 hour
    
    key.expiresAt = expiresAt;
    
    this.usageLog.push({
      type: 'refresh',
      deviceId,
      timestamp: now,
      expiresAt
    });
    
    return {
      expiresAt: Math.floor(expiresAt / 1000),
      expiresIn: 3600
    };
  }
  
  revokeKeys(deviceId: string): void {
    this.keys.delete(deviceId);
    
    this.usageLog.push({
      type: 'revoke',
      deviceId,
      timestamp: Date.now()
    });
  }
  
}
