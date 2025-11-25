export interface TTSProvider {
  getApiKey(): string;
  getBaseUrl(): string | undefined;
  getModel(): string;
  getVoice(): string;
  getProviderType(): string;
  getEndpoint(): string;
}

export interface TTSProviderConfig {
  provider: string;
  apiKey: string;
  baseUrl?: string;
  model?: string;
  voice?: string;
}

class OpenAITTSProvider implements TTSProvider {
  private apiKey: string;
  private baseUrl: string | undefined;
  private model: string;
  private voice: string;

  constructor(config: TTSProviderConfig) {
    this.apiKey = config.apiKey;
    this.baseUrl = config.baseUrl;
    this.model = config.model || 'tts-1'; // Default to tts-1 (faster and 50% cheaper than tts-1-hd)
    this.voice = config.voice || 'alloy';
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

  getVoice(): string {
    return this.voice;
  }

  getProviderType(): string {
    return 'openai';
  }

  getEndpoint(): string {
    const base = this.baseUrl || 'https://api.openai.com/v1';
    return `${base}/audio/speech`;
  }
}

class ElevenLabsTTSProvider implements TTSProvider {
  private apiKey: string;
  private baseUrl: string | undefined;
  private model: string;
  private voice: string;

  constructor(config: TTSProviderConfig) {
    this.apiKey = config.apiKey;
    this.baseUrl = config.baseUrl || 'https://api.elevenlabs.io/v1';
    this.model = config.model || 'eleven_multilingual_v2';
    this.voice = config.voice || '21m00Tcm4TlvDq8ikWAM'; // Default ElevenLabs voice
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

  getVoice(): string {
    return this.voice;
  }

  getProviderType(): string {
    return 'elevenlabs';
  }

  getEndpoint(): string {
    const base = this.baseUrl || 'https://api.elevenlabs.io/v1';
    return `${base}/text-to-speech/${this.voice}`;
  }
}

export function createTTSProvider(): TTSProvider {
  const provider = (process.env.TTS_PROVIDER || 'openai').toLowerCase();
  const apiKey = process.env.TTS_API_KEY;
  const baseUrl = process.env.TTS_BASE_URL;
  const model = process.env.TTS_MODEL;
  const voice = process.env.TTS_VOICE;

  if (!apiKey) {
    console.error('❌ TTS_API_KEY is not set in environment variables');
    console.log('💡 Please set TTS_API_KEY in laptop-app/.env or root .env');
    process.exit(1);
  }

  const config: TTSProviderConfig = {
    provider,
    apiKey,
    baseUrl,
    model,
    voice
  };

  switch (provider) {
    case 'openai':
      return new OpenAITTSProvider(config);
    
    case 'elevenlabs':
      return new ElevenLabsTTSProvider(config);
    
    default:
      console.error(`❌ Unknown TTS_PROVIDER: ${provider}`);
      console.log('💡 Supported providers: openai, elevenlabs');
      process.exit(1);
  }
}

