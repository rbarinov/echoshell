import { WebSocket, WebSocketServer } from 'ws';
import type { TerminalManager } from '../terminal/TerminalManager';
import type { OutputRouter } from '../output/OutputRouter';
import type { STTProvider } from '../keys/STTProvider';
import type { TTSProvider } from '../keys/TTSProvider';
import type { AIAgent } from '../agent/AIAgent';
import { transcribeAudio } from '../proxy/STTProxy';
import { synthesizeSpeech } from '../proxy/TTSProxy';

/**
 * WebSocket message types from client
 */
interface ExecuteMessage {
  type: 'execute';
  command?: string;
  audio?: string;        // base64 encoded (alternative to command)
  audio_format?: string;
  tts_enabled?: boolean;
  tts_speed?: number;
  language?: string;
}

interface InputMessage {
  type: 'input';
  data: string;
}

interface ResetContextMessage {
  type: 'reset_context';
}

type ClientMessage = ExecuteMessage | InputMessage | ResetContextMessage | { type: string; data?: string };

/**
 * Setup WebSocket server for terminal and agent streaming
 */
export function setupTerminalWebSocket(
  wss: WebSocketServer,
  terminalManager: TerminalManager,
  outputRouter: OutputRouter,
  sttProvider?: STTProvider,
  ttsProvider?: TTSProvider,
  aiAgent?: AIAgent
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

    const url = new URL(req.url || '', 'http://localhost');
    
    // Check if this is an agent WebSocket connection
    if (url.pathname === '/agent/ws') {
      handleAgentConnection(ws, sttProvider, ttsProvider, aiAgent, terminalManager);
      return;
    }

    // Otherwise, handle as terminal WebSocket
    const sessionIdMatch = url.pathname.match(/\/terminal\/([^\/]+)\/stream/);

    if (!sessionIdMatch) {
      ws.close(1008, 'Invalid path. Use /agent/ws or /terminal/{sessionId}/stream');
      return;
    }

    const sessionId = sessionIdMatch[1];
    handleTerminalConnection(ws, sessionId, terminalManager, outputRouter, sttProvider, ttsProvider);
  });
}

/**
 * Handle Agent WebSocket connection (no session required)
 */
function handleAgentConnection(
  ws: WebSocket,
  sttProvider?: STTProvider,
  ttsProvider?: TTSProvider,
  aiAgent?: AIAgent,
  terminalManager?: TerminalManager
): void {
  console.log('📡 Agent WebSocket connected');

  if (!aiAgent) {
    console.error('❌ AIAgent not configured');
    ws.send(JSON.stringify({ type: 'error', error: 'Agent not configured' }));
    ws.close(1008, 'Agent not configured');
    return;
  }

  ws.on('message', async (data) => {
    try {
      const message = JSON.parse(data.toString()) as ExecuteMessage;

      if (message.type === 'execute') {
        await handleAgentExecute(ws, message, sttProvider, ttsProvider, aiAgent, terminalManager);
      } else if (message.type === 'reset_context') {
        // Agent context reset (clear chat history)
        console.log('🔄 Agent context reset requested');
        ws.send(JSON.stringify({ type: 'context_reset', timestamp: Date.now() }));
      } else {
        console.warn(`⚠️ Unknown agent message type: ${message.type}`);
      }
    } catch (error) {
      console.error('❌ Agent WebSocket message error:', error);
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({
          type: 'error',
          error: error instanceof Error ? error.message : 'Unknown error',
          timestamp: Date.now()
        }));
      }
    }
  });

  ws.on('close', () => {
    console.log('📡 Agent WebSocket disconnected');
  });

  ws.on('error', (error) => {
    console.error('❌ Agent WebSocket error:', error);
  });
}

/**
 * Handle agent execute request
 * Supports: text OR audio input → streaming chunks → TTS audio output
 */
async function handleAgentExecute(
  ws: WebSocket,
  message: ExecuteMessage,
  sttProvider?: STTProvider,
  ttsProvider?: TTSProvider,
  aiAgent?: AIAgent,
  terminalManager?: TerminalManager
): Promise<void> {
  const { command, audio, language, tts_enabled, tts_speed } = message;

  let commandText = command || '';

  // Step 1: If audio provided, transcribe it
  if (audio && !command) {
    if (!sttProvider) {
      throw new Error('STT provider not configured');
    }

    console.log(`🎤 Agent: Transcribing audio (${audio.length} base64 chars)`);
    const audioBuffer = Buffer.from(audio, 'base64');
    commandText = await transcribeAudio(sttProvider, audioBuffer, language);

    // Send transcription to client
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({
        type: 'transcription',
        text: commandText,
        timestamp: Date.now()
      }));
    }

    console.log(`✅ Agent: Transcribed: "${commandText.substring(0, 50)}..."`);
  }

  if (!commandText) {
    throw new Error('No command or audio provided');
  }

  // Step 2: Execute agent command
  console.log(`🤖 Agent: Executing: "${commandText.substring(0, 50)}..."`);

  let agentResponse = '';
  try {
    const result = await aiAgent!.execute(commandText, undefined, terminalManager);
    agentResponse = result.output;

    // Send response as chunk (streaming - currently single chunk)
    // In future with streaming AIAgent, this would be multiple chunks
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({
        type: 'chunk',
        text: agentResponse,
        delta: agentResponse,
        timestamp: Date.now()
      }));
    }

    console.log(`✅ Agent: Response: "${agentResponse.substring(0, 50)}..."`);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Agent execution failed';
    throw new Error(`Agent execution failed: ${errorMessage}`);
  }

  // Step 3: Generate TTS for complete response
  let audioBase64: string | undefined;
  let audioFormat: string | undefined;

  if (tts_enabled && agentResponse && ttsProvider) {
    try {
      console.log(`🔊 Agent: Synthesizing TTS (${agentResponse.length} chars)`);
      const voice = ttsProvider.getVoice();
      const audioBuffer = await synthesizeSpeech(ttsProvider, agentResponse, voice, tts_speed || 1.0);
      audioBase64 = audioBuffer.toString('base64');
      audioFormat = 'audio/mpeg';
      console.log(`✅ Agent: TTS synthesized (${audioBuffer.length} bytes)`);
    } catch (error) {
      console.error('❌ Agent: TTS error:', error);
      // Don't fail the request, just skip audio
    }
  }

  // Step 4: Send complete message
  if (ws.readyState === WebSocket.OPEN) {
    const completeMessage: Record<string, unknown> = {
      type: 'complete',
      text: agentResponse,
      timestamp: Date.now()
    };

    if (audioBase64) {
      completeMessage.audio = audioBase64;
      completeMessage.audio_format = audioFormat;
    }

    ws.send(JSON.stringify(completeMessage));
  }

  console.log(`✅ Agent: Request completed, hasAudio=${!!audioBase64}`);
}

/**
 * Handle Terminal WebSocket connection (requires session ID)
 */
function handleTerminalConnection(
  ws: WebSocket,
  sessionId: string,
  terminalManager: TerminalManager,
  outputRouter: OutputRouter,
  sttProvider?: STTProvider,
  ttsProvider?: TTSProvider
): void {
  console.log(`📡 Terminal WebSocket connected for session: ${sessionId}`);

  // Add output listener for this WebSocket via OutputRouter
  const outputListener = (data: string) => {
    if (ws.readyState === WebSocket.OPEN) {
      // Check if data is already a chat_message or tts_audio format
      try {
        const parsed = JSON.parse(data);
        if (parsed.type === 'chat_message' || parsed.type === 'tts_audio') {
          ws.send(data);
          return;
        }
      } catch {
        // Not JSON, continue with output format
      }
      
      // Regular terminal output format
      ws.send(JSON.stringify({
        type: 'output',
        session_id: sessionId,
        data: data,
        timestamp: Date.now()
      }));
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
          if ('data' in message && message.data) {
            terminalManager.writeInput(sessionId, message.data);
          }
          break;

        case 'execute':
          await handleTerminalExecute(sessionId, message as ExecuteMessage, terminalManager, outputRouter, sttProvider, ttsProvider, ws);
          break;

        case 'reset_context':
          await handleResetContext(sessionId, terminalManager, ws);
          break;

        default:
          console.warn(`⚠️ Unknown terminal message type: ${message.type}`);
      }
    } catch (error) {
      console.error('❌ Terminal WebSocket message error:', error);
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
    console.log(`📡 Terminal WebSocket disconnected for session: ${sessionId}`);
    outputRouter.removeWebSocketListener(sessionId, outputListener);
  });

  ws.on('error', (error) => {
    console.error(`❌ Terminal WebSocket error for session ${sessionId}:`, error);
  });
}

/**
 * Handle terminal execute command
 */
async function handleTerminalExecute(
  sessionId: string,
  message: ExecuteMessage,
  terminalManager: TerminalManager,
  outputRouter: OutputRouter,
  sttProvider?: STTProvider,
  ttsProvider?: TTSProvider,
  ws?: WebSocket
): Promise<void> {
  const { command, audio, language, tts_enabled, tts_speed } = message;

  let commandText = command || '';

  // If audio provided, transcribe it
  if (audio && !command) {
    if (!sttProvider) {
      throw new Error('STT provider not configured');
    }

    console.log(`🎤 [Terminal] Transcribing audio (${audio.length} base64 chars)`);
    const audioBuffer = Buffer.from(audio, 'base64');
    commandText = await transcribeAudio(sttProvider, audioBuffer, language);

    // Send transcription to client
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({
        type: 'transcription',
        session_id: sessionId,
        text: commandText,
        timestamp: Date.now()
      }));
    }

    console.log(`✅ [Terminal] Transcribed: "${commandText.substring(0, 50)}..."`);
  }

  console.log(`🎯 [Terminal] Execute: "${commandText.substring(0, 50)}..." tts_enabled=${tts_enabled}`);

  // Store TTS settings for completion callback
  outputRouter.setSessionTtsSettings(sessionId, { 
    enabled: tts_enabled ?? true, 
    speed: tts_speed ?? 1.0, 
    language: language ?? 'en' 
  });

  // Execute command
  await terminalManager.executeCommand(sessionId, commandText);
}

/**
 * Handle reset context (agent/headless mode)
 */
async function handleResetContext(
  sessionId: string,
  terminalManager: TerminalManager,
  ws: WebSocket
): Promise<void> {
  console.log(`🔄 [Terminal] Reset context for session: ${sessionId}`);

  try {
    await terminalManager.clearChatHistory(sessionId);

    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({
        type: 'context_reset',
        session_id: sessionId,
        timestamp: Date.now()
      }));
    }

    console.log(`✅ [Terminal] Context reset confirmed for session: ${sessionId}`);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    console.error(`❌ [Terminal] Reset context error: ${errorMessage}`);

    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({
        type: 'error',
        session_id: sessionId,
        message: `Failed to reset context: ${errorMessage}`,
        timestamp: Date.now()
      }));
    }
  }
}
