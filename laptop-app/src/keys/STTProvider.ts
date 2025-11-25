export interface STTProvider {
  getApiKey(): string;
  getBaseUrl(): string | undefined;
  getModel(): string;
  getProviderType(): string;
  getEndpoint(): string;
}

export interface STTProviderConfig {
  provider: string;
  apiKey: string;
  baseUrl?: string;
  model?: string;
}

class OpenAISTTProvider implements STTProvider {
  private apiKey: string;
  private baseUrl: string | undefined;
  private model: string;

  constructor(config: STTProviderConfig) {
    this.apiKey = config.apiKey;
    this.baseUrl = config.baseUrl;
    this.model = config.model || 'whisper-1';
  }

  getApiKey(): string {
    return this.apiKey;
  }

  getBaseUrl(): string | undefined {
    return this.baseUrl;
  }

  getModel(): string {
    return this.model;
  }

  getProviderType(): string {
    return 'openai';
  }

  getEndpoint(): string {
    const base = this.baseUrl || 'https://api.openai.com/v1';
    return `${base}/audio/transcriptions`;
  }
}

class ElevenLabsSTTProvider implements STTProvider {
  private apiKey: string;
  private baseUrl: string | undefined;
  private model: string;

  constructor(config: STTProviderConfig) {
    this.apiKey = config.apiKey;
    this.baseUrl = config.baseUrl || 'https://api.elevenlabs.io/v1';
    this.model = config.model || 'eleven_multilingual_v2';
  }

  getApiKey(): string {
    return this.apiKey;
  }

  getBaseUrl(): string | undefined {
    return this.baseUrl;
  }

  getModel(): string {
    return this.model;
  }

  getProviderType(): string {
    return 'elevenlabs';
  }

  getEndpoint(): string {
    const base = this.baseUrl || 'https://api.elevenlabs.io/v1';
    return `${base}/speech-to-text`; // Adjust based on actual ElevenLabs API
  }
}

export function createSTTProvider(): STTProvider {
  const provider = (process.env.STT_PROVIDER || 'openai').toLowerCase();
  const apiKey = process.env.STT_API_KEY;
  const baseUrl = process.env.STT_BASE_URL;
  const model = process.env.STT_MODEL;

  if (!apiKey) {
    console.error('❌ STT_API_KEY is not set in environment variables');
    console.log('💡 Please set STT_API_KEY in laptop-app/.env or root .env');
    process.exit(1);
  }

  const config: STTProviderConfig = {
    provider,
    apiKey,
    baseUrl,
    model
  };

  switch (provider) {
    case 'openai':
      return new OpenAISTTProvider(config);
    
    case 'elevenlabs':
      return new ElevenLabsSTTProvider(config);
    
    default:
      console.error(`❌ Unknown STT_PROVIDER: ${provider}`);
      console.log('💡 Supported providers: openai, elevenlabs');
      process.exit(1);
  }
}

