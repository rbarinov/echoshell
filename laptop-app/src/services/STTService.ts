/**
 * Speech-to-Text Service using OpenAI Whisper API
 */

import OpenAI from 'openai';
import logger from '../utils/logger.js';
import fs from 'fs/promises';
import { createReadStream } from 'fs';
import path from 'path';
import os from 'os';

export interface TranscriptionResult {
  text: string;
  language?: string;
  duration?: number;
}

export class STTService {
  private client: OpenAI;

  constructor(apiKey: string) {
    this.client = new OpenAI({ apiKey });
  }

  /**
   * Transcribe audio buffer using OpenAI Whisper
   */
  async transcribe(
    audioBuffer: Buffer,
    format: 'wav' | 'm4a' | 'opus' = 'm4a'
  ): Promise<TranscriptionResult> {
    const tempFilePath = path.join(os.tmpdir(), `audio-${Date.now()}.${format}`);

    try {
      // Write buffer to temp file (OpenAI SDK requires file input)
      await fs.writeFile(tempFilePath, audioBuffer);

      logger.info('Transcribing audio', { format, size: audioBuffer.length });

      const transcription = await this.client.audio.transcriptions.create({
        file: createReadStream(tempFilePath) as any,
        model: 'whisper-1',
        language: 'en'
      });

      logger.info('Transcription successful', { text: transcription.text });

      return {
        text: transcription.text,
        language: 'en'
      };
    } catch (err) {
      const error = err instanceof Error ? err : new Error(String(err));
      logger.error('Transcription failed', error);
      throw new Error(`STT failed: ${error.message}`);
    } finally {
      // Clean up temp file
      try {
        await fs.unlink(tempFilePath);
      } catch (cleanupErr) {
        const cleanupError = cleanupErr instanceof Error ? cleanupErr : new Error(String(cleanupErr));
        logger.warn('Failed to cleanup temp file', { tempFilePath, error: cleanupError.message });
      }
    }
  }
}

