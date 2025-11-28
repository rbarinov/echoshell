import { WebSocket, WebSocketServer } from 'ws';
import type { TerminalManager } from '../terminal/TerminalManager';
import type { OutputRouter } from '../output/OutputRouter';
import type { STTProvider } from '../keys/STTProvider';
import type { TTSProvider } from '../keys/TTSProvider';
import { transcribeAudio } from '../proxy/STTProxy';
import { synthesizeSpeech } from '../proxy/TTSProxy';

/**
 * WebSocket message types from client
 */
interface ExecuteMessage {
  type: 'execute';
  command: string;
  tts_enabled?: boolean;
  tts_speed?: number;
  language?: string;
}

interface ExecuteAudioMessage {
  type: 'execute_audio';
  audio: string; // base64 encoded
  audio_format?: string;
  tts_enabled?: boolean;
  tts_speed?: number;
  language?: string;
}

interface InputMessage {
  type: 'input';
  data: string;
}

type ClientMessage = ExecuteMessage | ExecuteAudioMessage | InputMessage | { type: string; data?: string };

/**
 * Setup WebSocket server for terminal streaming (localhost only)
 */
export function setupTerminalWebSocket(
  wss: WebSocketServer,
  terminalManager: TerminalManager,
  outputRouter: OutputRouter,
  sttProvider?: STTProvider,
  ttsProvider?: TTSProvider
): void {
  wss.on('connection', (ws, req) => {
    // Check if connection is from localhost
    const clientIp = req.socket.remoteAddress || '';
    const isLocalhost =
      clientIp === '127.0.0.1' ||
      clientIp === '::1' ||
      clientIp === '::ffff:127.0.0.1';

    if (!isLocalhost) {
      console.warn(`⚠️  WebSocket connection rejected from non-localhost: ${clientIp}`);
      ws.close(1008, 'Access denied. WebSocket is only available on localhost.');
      return;
    }

    // Extract session ID from path
    const url = new URL(req.url || '', 'http://localhost');
    const sessionIdMatch = url.pathname.match(/\/terminal\/([^\/]+)\/stream/);

    if (!sessionIdMatch) {
      ws.close(1008, 'Invalid session ID');
      return;
    }

    const sessionId = sessionIdMatch[1];
    console.log(`📡 WebSocket connected for session: ${sessionId}`);

    // Store TTS settings for this session
    let sessionTtsEnabled = true;
    let sessionTtsSpeed = 1.0;
    let sessionLanguage = 'en';

    // Add output listener for this WebSocket via OutputRouter
    const outputListener = (data: string) => {
      if (ws.readyState === WebSocket.OPEN) {
        // Check if data is already a chat_message or tts_audio format
        try {
          const parsed = JSON.parse(data);
          if (parsed.type === 'chat_message' || parsed.type === 'tts_audio') {
            // Already in correct format, send as-is
            ws.send(data);
            return;
          }
        } catch {
          // Not JSON, continue with output format
        }
        
        // Regular terminal output format
        ws.send(
          JSON.stringify({
            type: 'output',
            session_id: sessionId,
            data: data,
            timestamp: Date.now()
          })
        );
      }
    };

    // Register WebSocket listener with OutputRouter
    outputRouter.addWebSocketListener(sessionId, outputListener);

    // Handle messages from client
    ws.on('message', async (data) => {
      try {
        const message = JSON.parse(data.toString()) as ClientMessage;

        switch (message.type) {
          case 'input':
            // Regular terminal input
            if ('data' in message && message.data) {
              terminalManager.writeInput(sessionId, message.data);
            }
            break;

          case 'execute':
            // Execute text command
            await handleExecuteCommand(
              sessionId,
              (message as ExecuteMessage).command,
              message as ExecuteMessage,
              terminalManager,
              outputRouter,
              ttsProvider,
              ws
            );
            break;

          case 'execute_audio':
            // Transcribe audio and execute
            await handleExecuteAudio(
              sessionId,
              message as ExecuteAudioMessage,
              terminalManager,
              outputRouter,
              sttProvider,
              ttsProvider,
              ws
            );
            break;

          default:
            console.warn(`⚠️ Unknown WebSocket message type: ${message.type}`);
        }
      } catch (error) {
        console.error('❌ Error processing WebSocket message:', error);
        // Send error to client
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({
            type: 'error',
            session_id: sessionId,
            message: error instanceof Error ? error.message : 'Unknown error',
            timestamp: Date.now()
          }));
        }
      }
    });

    ws.on('close', () => {
      console.log(`📡 WebSocket disconnected for session: ${sessionId}`);
      outputRouter.removeWebSocketListener(sessionId, outputListener);
    });

    ws.on('error', (error) => {
      console.error(`❌ WebSocket error for session ${sessionId}:`, error);
    });
  });
}

/**
 * Handle execute command (text)
 */
async function handleExecuteCommand(
  sessionId: string,
  command: string,
  options: ExecuteMessage,
  terminalManager: TerminalManager,
  outputRouter: OutputRouter,
  ttsProvider: TTSProvider | undefined,
  ws: WebSocket
): Promise<void> {
  const ttsEnabled = options.tts_enabled ?? true;
  const ttsSpeed = options.tts_speed ?? 1.0;
  const language = options.language ?? 'en';

  console.log(`🎯 [WS] Execute command: "${command.substring(0, 100)}..." tts_enabled=${ttsEnabled}`);

  // Store TTS settings for completion callback
  outputRouter.setSessionTtsSettings(sessionId, { enabled: ttsEnabled, speed: ttsSpeed, language });

  // Execute command
  await terminalManager.executeCommand(sessionId, command);
}

/**
 * Handle execute with audio (STT + execute)
 */
async function handleExecuteAudio(
  sessionId: string,
  message: ExecuteAudioMessage,
  terminalManager: TerminalManager,
  outputRouter: OutputRouter,
  sttProvider: STTProvider | undefined,
  ttsProvider: TTSProvider | undefined,
  ws: WebSocket
): Promise<void> {
  if (!sttProvider) {
    throw new Error('STT provider not configured');
  }

  const ttsEnabled = message.tts_enabled ?? true;
  const ttsSpeed = message.tts_speed ?? 1.0;
  const language = message.language ?? 'en';

  console.log(`🎤 [WS] Execute audio: transcribing ${message.audio.length} base64 chars, tts_enabled=${ttsEnabled}`);

  // Transcribe audio
  const audioBuffer = Buffer.from(message.audio, 'base64');
  const transcribedText = await transcribeAudio(sttProvider, audioBuffer, language);

  console.log(`🎤 [WS] Transcribed: "${transcribedText.substring(0, 100)}..."`);

  // Send transcription result to client
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({
      type: 'transcription',
      session_id: sessionId,
      text: transcribedText,
      timestamp: Date.now()
    }));
  }

  // Store TTS settings for completion callback
  outputRouter.setSessionTtsSettings(sessionId, { enabled: ttsEnabled, speed: ttsSpeed, language });

  // Execute transcribed command
  await terminalManager.executeCommand(sessionId, transcribedText);
}
