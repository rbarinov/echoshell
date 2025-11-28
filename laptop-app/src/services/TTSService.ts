/**
 * Text-to-Speech Service using OpenAI TTS API
 */

import OpenAI from 'openai';
import logger from '../utils/logger.js';

export class TTSService {
  private client: OpenAI;

  constructor(apiKey: string) {
    this.client = new OpenAI({ apiKey });
  }

  /**
   * Synthesize speech from text using OpenAI TTS
   */
  async synthesize(text: string, voice: 'alloy' | 'echo' | 'fable' | 'onyx' | 'nova' | 'shimmer' = 'alloy'): Promise<Buffer> {
    try {
      logger.info('Synthesizing speech', { textLength: text.length, voice });

      const response = await this.client.audio.speech.create({
        model: 'tts-1',
        voice,
        input: text,
        response_format: 'mp3'
      });

      const arrayBuffer = await response.arrayBuffer();
      const buffer = Buffer.from(arrayBuffer);

      logger.info('TTS synthesis successful', { audioSize: buffer.length });

      return buffer;
    } catch (err) {
      const error = err instanceof Error ? err : new Error(String(err));
      logger.error('TTS synthesis failed', error);
      throw new Error(`TTS failed: ${error.message}`);
    }
  }
}

