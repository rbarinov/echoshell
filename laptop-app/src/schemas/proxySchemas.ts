import { z } from 'zod';

export const STTTranscribeRequestSchema = z.object({
  audio: z.string().min(1, 'audio data is required (base64 encoded)'),
  language: z.string().optional()
});

export const TTSSynthesizeRequestSchema = z.object({
  text: z.string().min(1, 'text is required'),
  voice: z.string().optional(), // Ignored on server side, but accepted for compatibility
  speed: z.number().min(0.25).max(4.0).optional(),
  language: z.string().optional()
});

export type STTTranscribeRequest = z.infer<typeof STTTranscribeRequestSchema>;
export type TTSSynthesizeRequest = z.infer<typeof TTSSynthesizeRequestSchema>;
