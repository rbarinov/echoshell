import type { STTProvider } from '../keys/STTProvider';
import type { TTSProvider } from '../keys/TTSProvider';
import type { TunnelRequest, TunnelResponse } from '../types';
import { transcribeAudio } from '../proxy/STTProxy';
import { synthesizeSpeech } from '../proxy/TTSProxy';
import { STTTranscribeRequestSchema, TTSSynthesizeRequestSchema } from '../schemas/proxySchemas';
import { validateRequest } from '../utils/validation';
import logger from '../utils/logger';

export class ProxyHandler {
  constructor(
    private sttProvider: STTProvider,
    private ttsProvider: TTSProvider
  ) {}

  async handleRequest(req: TunnelRequest): Promise<TunnelResponse> {
    const { method, path, body } = req;

    if (path === '/proxy/stt/transcribe' && method === 'POST') {
      return this.handleSTTTranscribe(body);
    }

    if (path === '/proxy/tts/synthesize' && method === 'POST') {
      return this.handleTTSSynthesize(body);
    }

    return { statusCode: 404, body: { error: 'Not found' } };
  }

  private async handleSTTTranscribe(body: unknown): Promise<TunnelResponse> {
    try {
      const validation = validateRequest(STTTranscribeRequestSchema, body);
      if (!validation.success) {
        return validation.response;
      }

      const { audio, language } = validation.data;

      const audioData = Buffer.from(audio, 'base64');

      logger.info('STT Proxy: Received transcription request', { audioSize: audioData.length, language: language || 'auto' });

      const transcription = await transcribeAudio(this.sttProvider, audioData, language);

      return {
        statusCode: 200,
        body: {
          text: transcription
        }
      };
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      logger.error('STT Proxy error', error instanceof Error ? error : new Error(errorMessage));
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }

  private async handleTTSSynthesize(body: unknown): Promise<TunnelResponse> {
    try {
      const validation = validateRequest(TTSSynthesizeRequestSchema, body);
      if (!validation.success) {
        return validation.response;
      }

      const { text, speed, language } = validation.data;

      // Voice is always controlled by server configuration (TTS_VOICE env var)
      // Client cannot override voice - it's hardcoded on server side
      const serverVoice = this.ttsProvider.getVoice();

      // Speed validation will be done in synthesizeSpeech function
      // Pass speed as-is, it will be validated and clamped there
      const clientSpeed = speed ?? 1.0;

      logger.info('TTS Proxy: Received synthesis request', {
        textLength: text.length,
        voice: serverVoice,
        speed: clientSpeed,
        language: language || null
      });

      // Use server-configured voice only, speed from client (will be validated in synthesizeSpeech)
      const audioBuffer = await synthesizeSpeech(this.ttsProvider, text, serverVoice, clientSpeed);

      // Return audio as base64 for easy transmission
      return {
        statusCode: 200,
        body: {
          audio: audioBuffer.toString('base64'),
          format: 'audio/mpeg' // Adjust based on provider
        }
      };
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      logger.error('TTS Proxy error', error instanceof Error ? error : new Error(errorMessage));
      return { statusCode: 500, body: { error: errorMessage } };
    }
  }
}
