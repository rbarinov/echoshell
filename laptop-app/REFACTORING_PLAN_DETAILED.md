# Детальный План Рефакторинга Laptop App

## Обзор

Этот документ содержит детальный план исправления всех выявленных проблем, с конкретными шагами, примерами кода и архитектурными решениями.

---

## Фаза 1: Устранение Дублирования Обработки Вывода (КРИТИЧНО)

### Проблема

Сейчас для headless терминалов (`cursor_cli`, `claude_cli`) вывод обрабатывается дважды:

1. **TerminalManager** (строки 254-365):
   - Парсит JSON из PTY вывода
   - Извлекает assistant сообщения
   - Фильтрует результат
   - Отправляет через `sendTerminalOutput()` → `terminal_output`
   - Также отправляет через `emitHeadlessOutput()` → глобальные слушатели

2. **RecordingStreamManager** (строки 140-263):
   - Получает уже отфильтрованный текст через глобальные слушатели
   - Обрабатывает его снова
   - Отправляет через `sendRecordingOutput()` → `recording_output`

### Решение

**Централизовать всю обработку вывода в RecordingStreamManager**, а TerminalManager должен отправлять только сырой вывод.

### Шаг 1.1: Создать HeadlessOutputProcessor

**Новый файл:** `src/output/HeadlessOutputProcessor.ts`

```typescript
import type { TerminalType } from '../terminal/TerminalManager.js';

export interface ParsedHeadlessOutput {
  assistantText: string | null;
  sessionId: string | null;
  isResult: boolean;
  isComplete: boolean;
}

/**
 * Processes raw output from headless terminals (cursor_cli, claude_cli)
 * Extracts JSON, parses assistant messages, detects completion
 */
export class HeadlessOutputProcessor {
  /**
   * Parse a single line of output from headless terminal
   */
  parseLine(line: string, terminalType: TerminalType): ParsedHeadlessOutput {
    const trimmed = line.trim();
    if (!trimmed) {
      return {
        assistantText: null,
        sessionId: null,
        isResult: false,
        isComplete: false
      };
    }

    try {
      const payload = JSON.parse(trimmed);
      if (!payload || typeof payload !== 'object') {
        return {
          assistantText: null,
          sessionId: null,
          isResult: false,
          isComplete: false
        };
      }

      // Extract session_id
      const sessionId = this.extractSessionId(payload);

      // Check if this is a result message (completion)
      const isResult = payload.type === 'result' && payload.subtype === 'success';
      if (isResult) {
        return {
          assistantText: null,
          sessionId,
          isResult: true,
          isComplete: true
        };
      }

      // Extract assistant message text
      const assistantText = this.extractAssistantText(payload);
      
      return {
        assistantText,
        sessionId,
        isResult: false,
        isComplete: false
      };
    } catch (error) {
      // Not JSON, return as-is (might be shell output)
      return {
        assistantText: null,
        sessionId: null,
        isResult: false,
        isComplete: false
      };
    }
  }

  /**
   * Process multiple lines of output
   */
  processChunk(data: string, terminalType: TerminalType): {
    assistantMessages: string[];
    sessionId: string | null;
    isComplete: boolean;
    rawOutput: string; // For terminal display
  } {
    const lines = data.split('\n');
    const assistantMessages: string[] = [];
    let sessionId: string | null = null;
    let isComplete = false;
    const rawOutput: string[] = [];

    for (const line of lines) {
      const parsed = this.parseLine(line, terminalType);
      
      if (parsed.sessionId) {
        sessionId = parsed.sessionId;
      }

      if (parsed.isComplete) {
        isComplete = true;
        // Don't include result messages in output
        continue;
      }

      if (parsed.assistantText) {
        assistantMessages.push(parsed.assistantText);
        // Include assistant text in raw output (for terminal display)
        rawOutput.push(parsed.assistantText);
      } else {
        // Non-JSON or non-assistant output - include as-is
        rawOutput.push(line);
      }
    }

    return {
      assistantMessages,
      sessionId,
      isComplete,
      rawOutput: rawOutput.join('\n')
    };
  }

  private extractSessionId(payload: any): string | null {
    const candidates = [
      payload.session_id,
      payload.sessionId,
      payload.message?.session_id,
      payload.message?.sessionId,
      payload.result?.session_id,
      payload.result?.sessionId
    ];

    for (const candidate of candidates) {
      if (typeof candidate === 'string' && candidate.trim().length > 0) {
        return candidate.trim();
      }
    }

    return null;
  }

  private extractAssistantText(payload: any): string | null {
    if (payload.type !== 'assistant' || !payload.message?.content) {
      return null;
    }

    interface ContentBlock {
      type?: string;
      text?: string;
    }

    const parts = Array.isArray(payload.message.content)
      ? payload.message.content
          .map((block: ContentBlock) => {
            if (block.type === 'text' && block.text) {
              return block.text;
            }
            return null;
          })
          .filter((text: string | null): text is string => text !== null)
      : [];

    return parts.length > 0 ? parts.join('\n') : null;
  }
}
```

### Шаг 1.2: Рефакторинг TerminalManager

**Изменения в `TerminalManager.ts`:**

#### Удалить логику фильтрации для headless терминалов

**БЫЛО (строки 254-365):**
```typescript
// Capture output from shell for display
// For headless terminals, we need to parse JSON and extract session_id and assistant messages
pty.onData((data) => {
  session.outputBuffer.push(data);
  
  // Keep only last 10000 lines for history
  if (session.outputBuffer.length > 10000) {
    session.outputBuffer.shift();
  }

  // For headless terminals, filter output BEFORE sending to terminal
  // Only send assistant messages to terminal, not result messages or raw JSON
  if (this.isHeadlessTerminal(terminalType)) {
    // Process data line by line for JSON parsing
    const lines = data.split('\n');
    let terminalOutput = ''; // Accumulate only what should appear in terminal
    
    for (const line of lines) {
      const trimmedLine = line.trim();
      if (!trimmedLine) {
        terminalOutput += '\n';
        continue;
      }
      
      // Try to extract session_id
      const sessionId = this.extractSessionIdFromLine(trimmedLine, terminalType);
      if (sessionId && session.headless) {
        const previousSessionId = session.headless.cliSessionId;
        if (previousSessionId !== sessionId) {
          session.headless.cliSessionId = sessionId;
          console.log(`💾 [${session.sessionId}] Extracted and stored session_id from PTY output: ${sessionId}`);
        }
      }
      
      // Check for result message FIRST - don't send to terminal
      if (this.isResultMessage(trimmedLine, terminalType)) {
        console.log(`✅ [${session.sessionId}] Detected result message - command completed`);
        
        if (session.headless) {
          session.headless.isRunning = false;
          session.headless.lastResultSeen = true;
          if (session.headless.completionTimeout) {
            clearTimeout(session.headless.completionTimeout);
            session.headless.completionTimeout = undefined;
          }
        }
        
        console.log(`📤 [${session.sessionId}] Sending [COMMAND_COMPLETE] marker to recording stream`);
        this.emitHeadlessOutput(session, '[COMMAND_COMPLETE]');
        continue;
      }
      
      // Try to extract assistant message text (only for assistant type, not result)
      const text = this.extractAssistantTextFromLine(trimmedLine, terminalType);
      if (text) {
        console.log(`🎙️ [${session.sessionId}] Extracted assistant text from PTY: ${text.substring(0, 100)}...`);
        terminalOutput += text + '\n';
        this.emitHeadlessOutput(session, text);
      } else {
        // If it's not a result message and not an assistant message, it might be raw JSON
        try {
          JSON.parse(trimmedLine);
          console.log(`🔇 [${session.sessionId}] Skipping non-assistant JSON message from terminal output`);
          continue;
        } catch (e) {
          terminalOutput += line + '\n';
        }
      }
    }
    
    // Send filtered output to terminal (only assistant messages, no JSON)
    if (terminalOutput.trim().length > 0) {
      if (this.tunnelClient) {
        this.tunnelClient.sendTerminalOutput(session.sessionId, terminalOutput);
      }
      
      const listeners = this.outputListeners.get(session.sessionId);
      if (listeners) {
        listeners.forEach(listener => listener(terminalOutput));
      }
    }
  } else {
    // For regular terminals, send all output as-is
    // ... existing code ...
  }
});
```

**СТАНЕТ:**
```typescript
// Capture output from shell
pty.onData((data) => {
  session.outputBuffer.push(data);
  
  // Keep only last 10000 lines for history
  if (session.outputBuffer.length > 10000) {
    session.outputBuffer.shift();
  }

  // For ALL terminal types, send raw output to global listeners
  // RecordingStreamManager will handle filtering and processing
  this.globalOutputListeners.forEach(listener => {
    try {
      listener(session, data);
    } catch (error) {
      console.error('❌ Global output listener error:', error);
    }
  });

  // For terminal display (WebSocket and tunnel), send raw output
  // RecordingStreamManager will handle filtered output for TTS
  if (this.tunnelClient) {
    this.tunnelClient.sendTerminalOutput(session.sessionId, data);
  }
  
  const listeners = this.outputListeners.get(session.sessionId);
  if (listeners) {
    listeners.forEach(listener => listener(data));
  }
});
```

#### Удалить методы фильтрации

**Удалить методы:**
- `extractSessionIdFromLine()` (строки 868-905)
- `extractAssistantTextFromLine()` (строки 907-946)
- `isResultMessage()` (строки 948-966)
- `emitHeadlessOutput()` (строки 627-648) - больше не нужен

#### Упростить executeHeadlessCommand

**БЫЛО:**
```typescript
private async executeHeadlessCommand(session: TerminalSession, command: string): Promise<string> {
  // ... existing code ...
  
  // Mark command as started - completion will be detected from PTY output
  // We'll detect completion by looking for result messages or timeout
  // For now, just mark as started and let pty.onData handle the output
```

**СТАНЕТ:**
```typescript
private async executeHeadlessCommand(session: TerminalSession, command: string): Promise<string> {
  // ... existing code (command building) ...
  
  // Write command to PTY
  if (session.pty) {
    session.pty.write(commandLine);
    console.log(`📝 [${session.sessionId}] Wrote command to PTY: ${commandLine.trim()}`);
  } else {
    throw new Error('PTY not available for headless terminal');
  }
  
  // Completion detection will be handled by RecordingStreamManager
  // We just mark as running and set timeout
  session.headless.isRunning = true;
  
  // Set timeout for completion (fallback)
  if (session.headless.completionTimeout) {
    clearTimeout(session.headless.completionTimeout);
  }
  
  const completionTimeout = setTimeout(() => {
    if (session.headless?.isRunning) {
      console.log(`⏱️ [${session.sessionId}] Command completion timeout - marking as complete`);
      session.headless.isRunning = false;
      session.headless.completionTimeout = undefined;
    }
  }, 60000);
  
  session.headless.completionTimeout = completionTimeout;

  return 'Headless command started';
}
```

### Шаг 1.3: Рефакторинг RecordingStreamManager

**Изменения в `RecordingStreamManager.ts`:**

#### Добавить HeadlessOutputProcessor

```typescript
import { HeadlessOutputProcessor } from './HeadlessOutputProcessor.js';

export class RecordingStreamManager {
  private sessionStates = new Map<string, SessionState>();
  private headlessProcessor = new HeadlessOutputProcessor();

  // ... existing code ...
}
```

#### Переписать handleHeadlessOutput

**БЫЛО (строки 140-263):**
```typescript
private handleHeadlessOutput(sessionId: string, data: string): void {
  const text = data?.trim();
  
  // Check if this is a result message (JSON with type: "result")
  let isResultMessage = false;
  let resultText = '';
  try {
    const parsed = JSON.parse(text);
    if (parsed.type === 'result' && parsed.subtype === 'success' && !parsed.is_error) {
      isResultMessage = true;
      resultText = parsed.result || '';
      console.log(`✅✅✅ [${sessionId}] Detected result message in RecordingStreamManager: result=${resultText.length} chars`);
    }
  } catch (e) {
    // Not JSON, continue with normal processing
  }
  
  // ... много логики обработки ...
}
```

**СТАНЕТ:**
```typescript
private handleHeadlessOutput(sessionId: string, data: string, terminalType: TerminalType): void {
  const state = this.getSessionState(sessionId);
  
  // Process raw output using HeadlessOutputProcessor
  const processed = this.headlessProcessor.processChunk(data, terminalType);
  
  // Update session_id if found
  if (processed.sessionId) {
    // We need to update TerminalManager's session state
    // This will be handled via a callback or event
    this.updateHeadlessSessionId(sessionId, processed.sessionId);
  }
  
  // Handle completion
  if (processed.isComplete) {
    this.handleHeadlessCompletion(sessionId, state);
    return;
  }
  
  // Process assistant messages
  if (processed.assistantMessages.length > 0) {
    for (const message of processed.assistantMessages) {
      this.processAssistantMessage(sessionId, state, message);
    }
  }
  
  // Send filtered output to terminal display (via tunnel)
  if (processed.rawOutput.trim().length > 0) {
    const tunnelClient = this.tunnelClientResolver();
    if (tunnelClient) {
      tunnelClient.sendTerminalOutput(sessionId, processed.rawOutput);
    }
  }
}

private processAssistantMessage(sessionId: string, state: SessionState, message: string): void {
  // Check for duplicates
  if (state.lastHeadlessDelta === message && message.length > 0) {
    console.log(`⏭️ [${sessionId}] Duplicate assistant message, skipping`);
    return;
  }

  state.lastHeadlessDelta = message;
  
  // Append to accumulated text
  if (message.length > 0) {
    const previousLength = state.headlessFullText.length;
    state.headlessFullText =
      state.headlessFullText.length > 0 
        ? `${state.headlessFullText}\n\n${message}` 
        : message;
    console.log(`📝 [${sessionId}] Appended assistant text: ${previousLength} → ${state.headlessFullText.length} chars`);
  }

  // Broadcast to recording stream (for TTS)
  this.broadcastRecordingOutput(sessionId, {
    fullText: state.headlessFullText,
    delta: message,
    rawFiltered: message,
    isComplete: false
  });
}

private handleHeadlessCompletion(sessionId: string, state: SessionState): void {
  console.log(`✅ [${sessionId}] Command completed - sending final output for TTS`);
  
  let fullText = state.headlessFullText || '';
  
  if (fullText.length === 0) {
    console.warn(`⚠️ [${sessionId}] headlessFullText is empty when command completed`);
    const fallbackText = state.lastHeadlessDelta || '';
    if (fallbackText.length > 0) {
      console.log(`✅ [${sessionId}] Using fallback text for completion: ${fallbackText.length} chars`);
      fullText = fallbackText;
    }
  }
  
  // Send completion signal
  this.broadcastRecordingOutput(sessionId, {
    fullText: fullText,
    delta: '',
    rawFiltered: '',
    isComplete: true
  });
  
  // Reset state for next command
  state.lastHeadlessDelta = '';
  // Keep headlessFullText for potential retry or debugging
}

private updateHeadlessSessionId(sessionId: string, cliSessionId: string): void {
  // This needs to update TerminalManager's session state
  // We'll need to add a callback or use an event emitter
  // For now, we'll emit an event that TerminalManager can listen to
  // (This will be implemented in Phase 2)
}
```

#### Обновить handleTerminalOutput

**БЫЛО:**
```typescript
private handleTerminalOutput(sessionId: string, terminalType: TerminalType, data: string): void {
  if (terminalType === 'cursor_cli' || terminalType === 'claude_cli') {
    this.handleHeadlessOutput(sessionId, data);
    return;
  }
  // ... rest of code ...
}
```

**СТАНЕТ:**
```typescript
private handleTerminalOutput(sessionId: string, terminalType: TerminalType, data: string): void {
  if (terminalType === 'cursor_cli' || terminalType === 'claude_cli') {
    this.handleHeadlessOutput(sessionId, data, terminalType);
    return;
  }
  // ... rest of code for cursor_agent ...
}
```

### Шаг 1.4: Обновить конструктор RecordingStreamManager

**Нужно получить доступ к TerminalManager для обновления session_id:**

```typescript
export class RecordingStreamManager {
  constructor(
    terminalManager: TerminalManager,
    private readonly tunnelClientResolver: TunnelClientResolver
  ) {
    // Store reference to terminal manager for session_id updates
    this.terminalManager = terminalManager;
    
    terminalManager.addGlobalOutputListener((session, data) => {
      this.handleTerminalOutput(session.sessionId, session.terminalType, data);
    });

    terminalManager.addGlobalInputListener((session, data) => {
      this.handleTerminalInput(session.sessionId, data);
    });

    terminalManager.addSessionDestroyedListener((sessionId) => {
      this.sessionStates.delete(sessionId);
    });
  }
  
  private updateHeadlessSessionId(sessionId: string, cliSessionId: string): void {
    const session = this.terminalManager.getSession(sessionId);
    if (session?.headless) {
      const previousSessionId = session.headless.cliSessionId;
      if (previousSessionId !== cliSessionId) {
        session.headless.cliSessionId = cliSessionId;
        console.log(`💾 [${sessionId}] Updated CLI session_id: ${cliSessionId}`);
      }
    }
  }
}
```

---

## Фаза 2: Консолидация Передачи Вывода

### Проблема

Сейчас вывод отправляется через несколько путей:
- `tunnelClient.sendTerminalOutput()` - для отображения терминала
- `tunnelClient.sendRecordingOutput()` - для TTS
- `outputListeners` - для WebSocket (localhost)
- `globalOutputListeners` - для RecordingStreamManager

### Решение

Создать единый `OutputRouter`, который будет маршрутизировать вывод в нужные места.

### Шаг 2.1: Создать OutputRouter

**Новый файл:** `src/output/OutputRouter.ts`

```typescript
import type { TerminalManager, TerminalSession } from '../terminal/TerminalManager.js';
import type { TunnelClient } from '../tunnel/TunnelClient.js';

export interface OutputDestination {
  type: 'terminal_display' | 'recording_stream' | 'websocket';
  sessionId: string;
}

export interface OutputMessage {
  sessionId: string;
  data: string;
  destination: OutputDestination['type'];
  metadata?: {
    isComplete?: boolean;
    fullText?: string;
    delta?: string;
  };
}

/**
 * Routes terminal output to appropriate destinations
 * - terminal_display: Raw/filtered output for terminal UI (mobile + web)
 * - recording_stream: Processed output for TTS (mobile only)
 * - websocket: Output for localhost WebSocket connections
 */
export class OutputRouter {
  private websocketListeners = new Map<string, Set<(data: string) => void>>();
  
  constructor(
    private terminalManager: TerminalManager,
    private tunnelClient: TunnelClient | null
  ) {}

  /**
   * Register WebSocket listener for a session
   */
  addWebSocketListener(sessionId: string, listener: (data: string) => void): void {
    if (!this.websocketListeners.has(sessionId)) {
      this.websocketListeners.set(sessionId, new Set());
    }
    this.websocketListeners.get(sessionId)!.add(listener);
  }

  /**
   * Remove WebSocket listener
   */
  removeWebSocketListener(sessionId: string, listener: (data: string) => void): void {
    this.websocketListeners.get(sessionId)?.delete(listener);
  }

  /**
   * Route output to appropriate destinations
   */
  routeOutput(message: OutputMessage): void {
    switch (message.destination) {
      case 'terminal_display':
        this.sendToTerminalDisplay(message);
        break;
      case 'recording_stream':
        this.sendToRecordingStream(message);
        break;
      case 'websocket':
        this.sendToWebSocket(message);
        break;
    }
  }

  /**
   * Send output to terminal display (mobile + web via tunnel)
   */
  private sendToTerminalDisplay(message: OutputMessage): void {
    // Send to tunnel (for mobile)
    if (this.tunnelClient) {
      this.tunnelClient.sendTerminalOutput(message.sessionId, message.data);
    }
    
    // Send to WebSocket listeners (for localhost web UI)
    const listeners = this.websocketListeners.get(message.sessionId);
    if (listeners) {
      listeners.forEach(listener => listener(message.data));
    }
  }

  /**
   * Send output to recording stream (for TTS on mobile)
   */
  private sendToRecordingStream(message: OutputMessage): void {
    if (!this.tunnelClient) {
      return;
    }

    const payload = {
      text: message.metadata?.fullText || message.data,
      delta: message.metadata?.delta || message.data,
      raw: message.data,
      timestamp: Date.now(),
      isComplete: message.metadata?.isComplete || false
    };

    this.tunnelClient.sendRecordingOutput(message.sessionId, payload);
  }

  /**
   * Send output to WebSocket (localhost only)
   */
  private sendToWebSocket(message: OutputMessage): void {
    const listeners = this.websocketListeners.get(message.sessionId);
    if (listeners) {
      listeners.forEach(listener => listener(message.data));
    }
  }

  /**
   * Update tunnel client reference
   */
  setTunnelClient(tunnelClient: TunnelClient | null): void {
    this.tunnelClient = tunnelClient;
  }
}
```

### Шаг 2.2: Интегрировать OutputRouter в RecordingStreamManager

**Изменения в `RecordingStreamManager.ts`:**

```typescript
import { OutputRouter } from './OutputRouter.js';

export class RecordingStreamManager {
  constructor(
    terminalManager: TerminalManager,
    private readonly tunnelClientResolver: TunnelClientResolver,
    private outputRouter: OutputRouter
  ) {
    // ... existing code ...
  }

  private broadcastRecordingOutput(sessionId: string, result: RecordingProcessResult): void {
    // Use OutputRouter instead of direct tunnel client access
    this.outputRouter.routeOutput({
      sessionId,
      data: result.rawFiltered || result.delta,
      destination: 'recording_stream',
      metadata: {
        fullText: result.fullText,
        delta: result.delta,
        isComplete: result.isComplete
      }
    });
  }

  private handleHeadlessOutput(sessionId: string, data: string, terminalType: TerminalType): void {
    // ... processing logic ...
    
    // Send filtered output to terminal display via OutputRouter
    if (processed.rawOutput.trim().length > 0) {
      this.outputRouter.routeOutput({
        sessionId,
        data: processed.rawOutput,
        destination: 'terminal_display'
      });
    }
  }
}
```

### Шаг 2.3: Интегрировать OutputRouter в TerminalManager

**Изменения в `TerminalManager.ts`:**

```typescript
import type { OutputRouter } from '../output/OutputRouter.js';

export class TerminalManager {
  private outputRouter: OutputRouter | null = null;

  setOutputRouter(outputRouter: OutputRouter): void {
    this.outputRouter = outputRouter;
  }

  // In pty.onData handler:
  pty.onData((data) => {
    session.outputBuffer.push(data);
    
    if (session.outputBuffer.length > 10000) {
      session.outputBuffer.shift();
    }

    // Send raw output to global listeners (RecordingStreamManager)
    this.globalOutputListeners.forEach(listener => {
      try {
        listener(session, data);
      } catch (error) {
        console.error('❌ Global output listener error:', error);
      }
    });

    // For regular terminals, send raw output to terminal display
    // For headless terminals, RecordingStreamManager will handle filtered output
    if (!this.isHeadlessTerminal(session.terminalType)) {
      if (this.outputRouter) {
        this.outputRouter.routeOutput({
          sessionId: session.sessionId,
          data: data,
          destination: 'terminal_display'
        });
      }
    }
    // For headless terminals, output is handled by RecordingStreamManager
  });
}
```

### Шаг 2.4: Обновить index.ts для использования OutputRouter

**Изменения в `index.ts`:**

```typescript
import { OutputRouter } from './output/OutputRouter.js';

// Initialize OutputRouter
const outputRouter = new OutputRouter(terminalManager, null);

// Set tunnel client when available
tunnelClient = new TunnelClient(tunnelConfig, handleTunnelRequest, process.env.LAPTOP_AUTH_KEY);
await tunnelClient.connect();
outputRouter.setTunnelClient(tunnelClient);
terminalManager.setOutputRouter(outputRouter);

// Update RecordingStreamManager initialization
const recordingStreamManager = new RecordingStreamManager(
  terminalManager,
  () => tunnelClient,
  outputRouter
);

// Update WebSocket handler to use OutputRouter
wss.on('connection', (ws, req) => {
  // ... existing code ...
  
  const outputListener = (data: string) => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({
        type: 'output',
        session_id: sessionId,
        data: data,
        timestamp: Date.now()
      }));
    }
  };
  
  // Use OutputRouter instead of terminalManager.addOutputListener
  outputRouter.addWebSocketListener(sessionId, outputListener);
  
  ws.on('close', () => {
    outputRouter.removeWebSocketListener(sessionId, outputListener);
  });
});
```

---

## Фаза 3: Разделение index.ts

### Проблема

`index.ts` содержит 1385 строк и смешивает:
- Инициализацию сервера
- HTTP роутинг
- WebSocket обработку
- Обработчики запросов
- Логику туннеля

### Решение

Разделить на модули:
- `server.ts` - инициализация сервера
- `routes/` - HTTP роуты
- `handlers/` - обработчики запросов
- `websocket/` - WebSocket сервер

### Структура файлов

```
src/
  ├── index.ts (главная точка входа, только инициализация)
  ├── server.ts (создание HTTP/WebSocket сервера)
  ├── routes/
  │   ├── terminal.ts
  │   ├── keys.ts
  │   ├── workspace.ts
  │   └── agent.ts
  ├── handlers/
  │   ├── terminalHandler.ts
  │   ├── keyHandler.ts
  │   ├── workspaceHandler.ts
  │   └── agentHandler.ts
  └── websocket/
      └── terminalWebSocket.ts
```

### Шаг 3.1: Создать server.ts

**Новый файл:** `src/server.ts`

```typescript
import express from 'express';
import { createServer, Server } from 'http';
import { WebSocketServer } from 'ws';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export interface ServerConfig {
  port: number;
  publicDir: string;
}

export function createAppServer(config: ServerConfig): {
  app: express.Application;
  server: Server;
  wss: WebSocketServer;
} {
  const app = express();
  app.use(express.json());

  const server = createServer(app);
  const wss = new WebSocketServer({ server });

  // Serve static files
  app.use(express.static(config.publicDir));

  return { app, server, wss };
}

export function startServer(
  server: Server,
  port: number,
  host: string = '127.0.0.1'
): Promise<void> {
  return new Promise((resolve) => {
    server.listen(port, host, () => {
      console.log(`🌐 Server listening on http://${host}:${port}`);
      resolve();
    });
  });
}
```

### Шаг 3.2: Создать routes/terminal.ts

**Новый файл:** `src/routes/terminal.ts`

```typescript
import { Router } from 'express';
import type { TerminalManager } from '../terminal/TerminalManager.js';

export function createTerminalRoutes(terminalManager: TerminalManager): Router {
  const router = Router();

  router.get('/list', async (_req, res) => {
    try {
      const sessions = terminalManager.listSessions();
      res.json({
        sessions: sessions.map(s => ({
          session_id: s.sessionId,
          working_dir: s.workingDir,
          terminal_type: s.terminalType,
          name: s.name,
          created_at: s.createdAt || Date.now()
        }))
      });
    } catch (error) {
      res.status(500).json({ error: 'Failed to list sessions' });
    }
  });

  router.post('/create', async (req, res) => {
    try {
      const { terminal_type, working_dir, name } = req.body;
      // ... validation ...
      const session = await terminalManager.createSession(terminal_type, working_dir, name);
      res.json({
        session_id: session.sessionId,
        working_dir: session.workingDir,
        terminal_type: session.terminalType,
        name: session.name,
        status: 'created'
      });
    } catch (error) {
      res.status(500).json({ error: 'Failed to create session' });
    }
  });

  // ... остальные роуты ...

  return router;
}
```

### Шаг 3.3: Создать handlers/terminalHandler.ts

**Новый файл:** `src/handlers/terminalHandler.ts`

```typescript
import type { TerminalManager } from '../terminal/TerminalManager.js';
import type { TunnelRequest, TunnelResponse } from '../types.js';

export class TerminalHandler {
  constructor(private terminalManager: TerminalManager) {}

  async handleRequest(req: TunnelRequest): Promise<TunnelResponse> {
    const { method, path } = req;

    if (path === '/terminal/list' && method === 'GET') {
      return this.handleList();
    }

    if (path === '/terminal/create' && method === 'POST') {
      return this.handleCreate(req.body);
    }

    // ... остальные обработчики ...

    return { statusCode: 404, body: { error: 'Not found' } };
  }

  private handleList(): TunnelResponse {
    const sessions = this.terminalManager.listSessions();
    return {
      statusCode: 200,
      body: {
        sessions: sessions.map(s => ({
          session_id: s.sessionId,
          working_dir: s.workingDir,
          terminal_type: s.terminalType,
          name: s.name
        }))
      }
    };
  }

  private async handleCreate(body: unknown): Promise<TunnelResponse> {
    const bodyObj = body as { terminal_type?: string; working_dir?: string; name?: string };
    // ... validation ...
    const session = await this.terminalManager.createSession(
      bodyObj.terminal_type,
      bodyObj.working_dir,
      bodyObj.name
    );
    return {
      statusCode: 200,
      body: {
        session_id: session.sessionId,
        working_dir: session.workingDir,
        terminal_type: session.terminalType,
        name: session.name,
        status: 'created'
      }
    };
  }
}
```

### Шаг 3.4: Обновить index.ts

**Новый `index.ts` (упрощенный):**

```typescript
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import { createAppServer, startServer } from './server.js';
import { createTerminalRoutes } from './routes/terminal.js';
import { TerminalHandler } from './handlers/terminalHandler.js';
// ... другие импорты ...

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load environment variables
dotenv.config({ path: path.resolve(__dirname, '../.env') });
dotenv.config({ path: path.resolve(__dirname, '../../.env'), override: false });

// Initialize components
const stateManager = new StateManager();
const terminalManager = new TerminalManager(stateManager);
// ... другие инициализации ...

// Create server
const WEB_PORT = parseInt(process.env.WEB_INTERFACE_PORT || '8002', 10);
const publicDir = path.resolve(__dirname, '../public');

const { app, server, wss } = createAppServer({
  port: WEB_PORT,
  publicDir
});

// Setup routes
app.use('/terminal', createTerminalRoutes(terminalManager));
// ... другие роуты ...

// Setup WebSocket
setupTerminalWebSocket(wss, terminalManager, outputRouter);

// Setup tunnel
await initializeTunnel();

// Start server
await startServer(server, WEB_PORT);
console.log('✅ Laptop application ready!');
```

---

## Фаза 4: Улучшение Типобезопасности

### Шаг 4.1: Добавить Zod схемы

**Новый файл:** `src/schemas/terminalSchemas.ts`

```typescript
import { z } from 'zod';

export const CreateSessionSchema = z.object({
  terminal_type: z.enum(['regular', 'cursor_agent', 'cursor_cli', 'claude_cli']),
  working_dir: z.string().optional(),
  name: z.string().optional()
});

export const ExecuteCommandSchema = z.object({
  command: z.string()
});

export const RenameSessionSchema = z.object({
  name: z.string().min(1)
});

export type CreateSessionRequest = z.infer<typeof CreateSessionSchema>;
export type ExecuteCommandRequest = z.infer<typeof ExecuteCommandSchema>;
export type RenameSessionRequest = z.infer<typeof RenameSessionSchema>;
```

### Шаг 4.2: Использовать схемы в обработчиках

```typescript
import { CreateSessionSchema, ExecuteCommandSchema } from '../schemas/terminalSchemas.js';

private async handleCreate(body: unknown): Promise<TunnelResponse> {
  try {
    const validated = CreateSessionSchema.parse(body);
    const session = await this.terminalManager.createSession(
      validated.terminal_type,
      validated.working_dir,
      validated.name
    );
    return {
      statusCode: 200,
      body: { /* ... */ }
    };
  } catch (error) {
    if (error instanceof z.ZodError) {
      return {
        statusCode: 400,
        body: { error: 'Invalid request', details: error.errors }
      };
    }
    throw error;
  }
}
```

---

## Фаза 5: Структурированное Логирование

### Шаг 5.1: Создать Logger

**Новый файл:** `src/utils/logger.ts`

```typescript
export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3
}

export interface LogContext {
  sessionId?: string;
  operation?: string;
  [key: string]: unknown;
}

export class Logger {
  constructor(private level: LogLevel = LogLevel.INFO) {}

  debug(message: string, context?: LogContext): void {
    if (this.level <= LogLevel.DEBUG) {
      this.log('DEBUG', message, context);
    }
  }

  info(message: string, context?: LogContext): void {
    if (this.level <= LogLevel.INFO) {
      this.log('INFO', message, context);
    }
  }

  warn(message: string, context?: LogContext): void {
    if (this.level <= LogLevel.WARN) {
      this.log('WARN', message, context);
    }
  }

  error(message: string, context?: LogContext, error?: Error): void {
    if (this.level <= LogLevel.ERROR) {
      this.log('ERROR', message, { ...context, error: error?.message, stack: error?.stack });
    }
  }

  private log(level: string, message: string, context?: LogContext): void {
    const timestamp = new Date().toISOString();
    const contextStr = context ? ` ${JSON.stringify(context)}` : '';
    console.log(`[${timestamp}] [${level}] ${message}${contextStr}`);
  }
}

export const logger = new Logger(
  process.env.LOG_LEVEL === 'debug' ? LogLevel.DEBUG : LogLevel.INFO
);
```

### Шаг 5.2: Использовать Logger везде

```typescript
import { logger } from '../utils/logger.js';

// Вместо:
console.log(`✅ Created terminal session: ${sessionId}`);

// Использовать:
logger.info('Created terminal session', { sessionId, terminalType });
```

---

## Порядок Выполнения

### Неделя 1: Критичные исправления

**День 1-2: Фаза 1 (Устранение дублирования)**
- [ ] Создать `HeadlessOutputProcessor`
- [ ] Рефакторить `TerminalManager` (удалить фильтрацию)
- [ ] Рефакторить `RecordingStreamManager` (добавить обработку)
- [ ] Тестирование

**День 3-4: Фаза 2 (Консолидация передачи)**
- [ ] Создать `OutputRouter`
- [ ] Интегрировать в `RecordingStreamManager`
- [ ] Интегрировать в `TerminalManager`
- [ ] Обновить `index.ts`
- [ ] Тестирование

**День 5: Тестирование и исправление багов**
- [ ] Интеграционное тестирование
- [ ] Исправление найденных проблем
- [ ] Проверка производительности

### Неделя 2: Рефакторинг структуры

**День 1-2: Фаза 3 (Разделение index.ts)**
- [ ] Создать `server.ts`
- [ ] Создать `routes/`
- [ ] Создать `handlers/`
- [ ] Обновить `index.ts`
- [ ] Тестирование

**День 3: Фаза 4 (Типобезопасность)**
- [ ] Создать Zod схемы
- [ ] Обновить обработчики
- [ ] Тестирование

**День 4-5: Фаза 5 (Логирование)**
- [ ] Создать Logger
- [ ] Заменить все console.log
- [ ] Тестирование

---

## Тестирование

### Unit тесты

```typescript
// tests/output/HeadlessOutputProcessor.test.ts
describe('HeadlessOutputProcessor', () => {
  it('should extract assistant messages from JSON', () => {
    const processor = new HeadlessOutputProcessor();
    const json = JSON.stringify({
      type: 'assistant',
      message: { content: [{ type: 'text', text: 'Hello' }] }
    });
    const result = processor.parseLine(json, 'cursor_cli');
    expect(result.assistantText).toBe('Hello');
  });
});
```

### Интеграционные тесты

```typescript
// tests/integration/outputFlow.test.ts
describe('Output Flow Integration', () => {
  it('should process headless output without duplication', async () => {
    // Create headless session
    // Send command
    // Verify output is processed once
    // Verify both terminal_output and recording_output are sent
  });
});
```

---

## Метрики Успеха

1. **Устранение дублирования:**
   - Вывод headless терминалов обрабатывается один раз
   - Нет дублирующихся сообщений в логах

2. **Улучшение архитектуры:**
   - `index.ts` < 200 строк
   - Каждый класс < 500 строк
   - Четкое разделение ответственности

3. **Типобезопасность:**
   - Все внешние данные валидируются
   - Нет type assertions без проверки

4. **Производительность:**
   - Нет деградации производительности
   - Память не растет (нет утечек слушателей)

---

## Риски и Митигация

### Риск 1: Регрессии в функциональности
**Митигация:** Тщательное тестирование перед каждым изменением

### Риск 2: Проблемы с производительностью
**Митигация:** Профилирование до и после изменений

### Риск 3: Сложность интеграции изменений
**Митигация:** Поэтапное внедрение, возможность отката

---

## Заключение

Этот план обеспечивает:
1. Устранение критичных проблем с дублированием
2. Улучшение архитектуры и поддерживаемости
3. Постепенное внедрение без нарушения работы
4. Четкие метрики успеха

Каждый этап можно выполнять независимо и тестировать отдельно.
