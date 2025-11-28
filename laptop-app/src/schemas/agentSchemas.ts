import { z } from 'zod';

/**
 * Schema for /agent/execute endpoint
 * Supports either text command OR audio input
 * Can optionally return TTS audio in response
 */
export const ExecuteAgentRequestSchema = z.object({
  // Input: either command (text) or audio (base64) - at least one required
  command: z.string().optional(),
  audio: z.string().optional(), // base64 encoded audio
  audio_format: z.string().optional(), // e.g., "audio/m4a"
  language: z.string().optional(), // language for STT, e.g., "en", "ru"
  
  // TTS options
  tts_enabled: z.boolean().optional().default(false),
  tts_speed: z.number().optional().default(1.0),
  
  // Optional session context (for terminal integration)
  session_id: z.string().optional()
}).refine(
  (data) => data.command || data.audio,
  { message: 'Either command (text) or audio must be provided' }
);

export type ExecuteAgentRequest = z.infer<typeof ExecuteAgentRequestSchema>;
