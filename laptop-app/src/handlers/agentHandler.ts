import type { AIAgent } from '../agent/AIAgent';
import type { TerminalManager } from '../terminal/TerminalManager';
import type { STTProvider } from '../keys/STTProvider';
import type { TTSProvider } from '../keys/TTSProvider';
import type { TunnelRequest, TunnelResponse } from '../types';
import { ExecuteAgentRequestSchema } from '../schemas/agentSchemas';
import { transcribeAudio } from '../proxy/STTProxy';
import { synthesizeSpeech } from '../proxy/TTSProxy';
import { validateRequest } from '../utils/validation';
import logger from '../utils/logger';

export class AgentHandler {
  constructor(
    private aiAgent: AIAgent,
    private terminalManager: TerminalManager,
    private sttProvider?: STTProvider,
    private ttsProvider?: TTSProvider
  ) {}

  async handleRequest(req: TunnelRequest): Promise<TunnelResponse> {
    const { method, path, body } = req;

    if (path === '/agent/execute' && method === 'POST') {
      return this.handleExecute(body);
    }

    return { statusCode: 404, body: { error: 'Not found' } };
  }

  private async handleExecute(body: unknown): Promise<TunnelResponse> {
    const validation = validateRequest(ExecuteAgentRequestSchema, body);
    if (!validation.success) {
      return validation.response;
    }

    const { 
      command, 
      audio, 
      audio_format,
      language, 
      tts_enabled, 
      tts_speed, 
      session_id 
    } = validation.data;

    let commandText = command || '';
    let transcription: string | undefined;

    // Step 1: If audio provided, transcribe it first
    if (audio && !command) {
      if (!this.sttProvider) {
        return {
          statusCode: 500,
          body: { error: 'STT provider not configured' }
        };
      }

      try {
        logger.info('Agent: Transcribing audio input', { 
          audioSize: audio.length, 
          language: language || 'auto' 
        });
        
        const audioBuffer = Buffer.from(audio, 'base64');
        transcription = await transcribeAudio(this.sttProvider, audioBuffer, language);
        commandText = transcription;
        
        logger.info('Agent: Audio transcribed', { 
          transcription: transcription.substring(0, 100) 
        });
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : 'Transcription failed';
        logger.error('Agent: STT error', error instanceof Error ? error : new Error(errorMessage));
        return {
          statusCode: 500,
          body: { error: `Transcription failed: ${errorMessage}` }
        };
      }
    }

    // Step 2: Execute agent command
    logger.info('AI Agent executing', { 
      command: commandText.substring(0, 100), 
      sessionId: session_id || null,
      ttsEnabled: tts_enabled 
    });

    let agentResult: string;
    try {
      const result = await this.aiAgent.execute(commandText, session_id, this.terminalManager);
      agentResult = result.output;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Agent execution failed';
      logger.error('Agent: Execution error', error instanceof Error ? error : new Error(errorMessage));
      return {
        statusCode: 500,
        body: { error: `Agent execution failed: ${errorMessage}` }
      };
    }

    // Step 3: If TTS enabled, synthesize audio response
    let audioResponse: string | undefined;
    let audioFormat: string | undefined;

    if (tts_enabled && agentResult) {
      if (!this.ttsProvider) {
        logger.warn('Agent: TTS requested but provider not configured');
      } else {
        try {
          logger.info('Agent: Synthesizing TTS response', { 
            textLength: agentResult.length,
            speed: tts_speed 
          });
          
          const voice = this.ttsProvider.getVoice();
          const audioBuffer = await synthesizeSpeech(
            this.ttsProvider, 
            agentResult, 
            voice, 
            tts_speed || 1.0
          );
          
          audioResponse = audioBuffer.toString('base64');
          audioFormat = 'audio/mpeg';
          
          logger.info('Agent: TTS synthesized', { 
            audioSize: audioBuffer.length 
          });
        } catch (error) {
          const errorMessage = error instanceof Error ? error.message : 'TTS synthesis failed';
          logger.error('Agent: TTS error', error instanceof Error ? error : new Error(errorMessage));
          // Don't fail the whole request, just skip TTS
        }
      }
    }

    // Build response
    const responseBody: Record<string, unknown> = {
      result: agentResult,
    };

    // Include transcription if audio was input
    if (transcription) {
      responseBody.transcription = transcription;
    }

    // Include audio if TTS was generated
    if (audioResponse) {
      responseBody.audio = audioResponse;
      responseBody.audio_format = audioFormat;
    }

    return {
      statusCode: 200,
      body: responseBody
    };
  }
}
