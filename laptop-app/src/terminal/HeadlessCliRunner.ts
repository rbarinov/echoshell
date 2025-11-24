import { spawn } from 'child_process';
import readline from 'readline';

export type HeadlessTerminalType = 'cursor_cli' | 'claude_cli';

interface HeadlessRunOptions {
  sessionId: string;
  workingDir: string;
  terminalType: HeadlessTerminalType;
  prompt: string;
  onDelta: (text: string) => void;
  onError?: (message: string) => void;
}

export class HeadlessCliRunner {
  async run(options: HeadlessRunOptions): Promise<void> {
    const { binary, args } = this.buildCommand(options.terminalType, options.prompt);

    return new Promise((resolve, reject) => {
      console.log(`🤖 [${options.sessionId}] Starting ${options.terminalType} headless run...`);
      const child = spawn(binary, args, {
        cwd: options.workingDir || process.cwd(),
        env: {
          ...process.env,
          FORCE_COLOR: '0'
        }
      });

      child.on('error', (error) => {
        const message = `❌ Headless CLI failed to start (${binary}): ${error.message}`;
        console.error(message);
        options.onError?.(message);
        reject(error);
      });

      const stdout = readline.createInterface({ input: child.stdout });
      stdout.on('line', (line) => {
        const text = this.extractText(line, options.terminalType);
        if (text) {
          options.onDelta(text);
        }
      });

      child.stderr.on('data', (data: Buffer) => {
        const message = data.toString().trim();
        if (message.length > 0) {
          console.warn(`⚠️ [${options.sessionId}] ${options.terminalType} stderr: ${message}`);
          options.onError?.(message);
        }
      });

      child.on('close', (code) => {
        if (code === 0) {
          console.log(`✅ [${options.sessionId}] ${options.terminalType} headless run finished`);
          resolve();
        } else {
          const error = new Error(`${options.terminalType} exited with code ${code ?? 'unknown'}`);
          console.error(`❌ [${options.sessionId}] ${error.message}`);
          options.onError?.(error.message);
          reject(error);
        }
      });
    });
  }

  private buildCommand(terminalType: HeadlessTerminalType, prompt: string): { binary: string; args: string[] } {
    if (terminalType === 'cursor_cli') {
      const binary = process.env.CURSOR_HEADLESS_BIN || process.env.CURSOR_AGENT_BINARY || 'cursor-agent';
      const extraArgs = this.parseExtraArgs(process.env.CURSOR_HEADLESS_EXTRA_ARGS);
      const args = [
        '-p',
        prompt,
        '--force',
        '--output-format',
        'stream-json',
        '--stream-partial-output',
        ...extraArgs
      ];
      return { binary, args };
    }

    const binary = process.env.CLAUDE_HEADLESS_BIN || 'claude';
    const extraArgs = this.parseExtraArgs(process.env.CLAUDE_HEADLESS_EXTRA_ARGS);
    const args = ['-p', prompt, '--output-format', 'stream-json', ...extraArgs];
    return { binary, args };
  }

  private parseExtraArgs(value?: string): string[] {
    if (!value) {
      return [];
    }

    return value
      .split(' ')
      .map((token) => token.trim())
      .filter((token) => token.length > 0);
  }

  private extractText(line: string, terminalType: HeadlessTerminalType): string | null {
    if (!line || line.trim().length === 0) {
      return null;
    }

    try {
      const payload = JSON.parse(line);
      if (terminalType === 'cursor_cli') {
        return this.extractCursorText(payload);
      }
      return this.extractClaudeText(payload);
    } catch (error) {
      console.warn(`⚠️ Failed to parse headless output: ${line}`);
      return null;
    }
  }

  private extractCursorText(payload: any): string | null {
    if (!payload || typeof payload !== 'object') {
      return null;
    }

    if (payload.type === 'assistant' && payload.message?.content) {
      const parts = Array.isArray(payload.message.content)
        ? payload.message.content
            .map((block: any) => block?.text ?? '')
            .filter((text: string) => typeof text === 'string')
        : [];
      const text = parts.join('').trim();
      if (text.length > 0) {
        return text;
      }
    }

    if (payload.type === 'result') {
      const candidates = [
        payload.result?.summary,
        payload.result?.text,
        payload.summary,
        payload.result
      ].filter((value): value is string => typeof value === 'string' && value.trim().length > 0);

      if (candidates.length > 0) {
        return candidates[0].trim();
      }
    }

    return this.extractGenericText(payload);
  }

  private extractClaudeText(payload: any): string | null {
    if (!payload || typeof payload !== 'object') {
      return null;
    }

    if (payload.type === 'result' && typeof payload.result === 'string' && payload.result.trim().length > 0) {
      return payload.result.trim();
    }

    if (payload.type === 'assistant' && payload.message?.content) {
      const textBlocks = Array.isArray(payload.message.content)
        ? payload.message.content
            .map((block: any) => block?.text ?? '')
            .filter((text: string) => typeof text === 'string')
        : [];
      const text = textBlocks.join('').trim();
      if (text.length > 0) {
        return text;
      }
    }

    if (payload.delta?.text && typeof payload.delta.text === 'string') {
      const text = payload.delta.text.trim();
      if (text.length > 0) {
        return text;
      }
    }

    return this.extractGenericText(payload);
  }

  private extractGenericText(payload: any): string | null {
    const collected: string[] = [];

    const visit = (node: any, keyPath: string[] = []) => {
      if (typeof node === 'string') {
        const text = node.trim();
        if (text.length > 0) {
          collected.push(text);
        }
        return;
      }

      if (Array.isArray(node)) {
        node.forEach((item) => visit(item, keyPath));
        return;
      }

      if (node && typeof node === 'object') {
        Object.entries(node).forEach(([key, value]) => {
          if (this.shouldExtractFromKey(key)) {
            visit(value, [...keyPath, key]);
          }
        });
      }
    };

    visit(payload);

    if (collected.length === 0) {
      return null;
    }

    collected.sort((a, b) => b.length - a.length);
    return collected[0];
  }

  private shouldExtractFromKey(key: string): boolean {
    const normalized = key.toLowerCase();
    return (
      normalized.includes('text') ||
      normalized.includes('result') ||
      normalized.includes('summary') ||
      normalized.includes('output') ||
      normalized.includes('message') ||
      normalized.includes('content')
    );
  }
}
