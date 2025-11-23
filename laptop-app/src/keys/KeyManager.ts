import crypto from 'crypto';

interface EphemeralKey {
  deviceId: string;
  openaiKey: string;
  elevenLabsKey?: string;
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
    private masterOpenAIKey: string,
    private masterElevenLabsKey?: string
  ) {}
  
  issueEphemeralKeys(deviceId: string, durationSeconds: number, permissions: string[]): {
    openaiKey: string;
    elevenLabsKey?: string;
    expiresAt: number;
    expiresIn: number;
    permissions: string[];
  } {
    const now = Date.now();
    const expiresAt = now + (durationSeconds * 1000);
    
    // For now, we'll use the master keys as ephemeral keys
    // In production, you'd want to create actual ephemeral OpenAI keys via API
    const ephemeralKey: EphemeralKey = {
      deviceId,
      openaiKey: this.masterOpenAIKey,
      elevenLabsKey: this.masterElevenLabsKey,
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
      openaiKey: ephemeralKey.openaiKey,
      elevenLabsKey: ephemeralKey.elevenLabsKey,
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
  
  validateKey(deviceId: string): boolean {
    const key = this.keys.get(deviceId);
    
    if (!key) {
      return false;
    }
    
    if (Date.now() > key.expiresAt) {
      this.keys.delete(deviceId);
      return false;
    }
    
    return true;
  }
  
  getUsageLog(): UsageLogEntry[] {
    return this.usageLog;
  }
}
