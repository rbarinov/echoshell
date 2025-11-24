/**
 * TerminalScreenEmulator
 * ----------------------
 * Minimal terminal screen emulator that processes ANSI escape sequences
 * to maintain the final rendered screen state. This mirrors the Swift
 * implementation used on iOS for the recording view so that we can
 * centralize the logic on the backend.
 */

type CSIHandler = (params: string) => void;

export class TerminalScreenEmulator {
  private screen: string[] = [];
  private cursorRow = 0;
  private cursorCol = 0;
  private readonly maxLines = 1000;

  processOutput(text: string): void {
    let remaining = text;

    while (remaining.length > 0) {
      const escIndex = remaining.indexOf('\u001B');
      if (escIndex === -1) {
        this.writeText(remaining);
        break;
      }

      const beforeEsc = remaining.slice(0, escIndex);
      if (beforeEsc.length > 0) {
        this.writeText(beforeEsc);
      }

      const afterEsc = remaining.slice(escIndex + 1);
      const consumed = this.processEscapeSequence(afterEsc);
      if (consumed !== null) {
        remaining = afterEsc.slice(consumed);
      } else {
        remaining = afterEsc;
      }
    }
  }

  getScreenContent(): string {
    const lines = [...this.screen];
    while (lines.length > 0 && lines[lines.length - 1].trim().length === 0) {
      lines.pop();
    }
    return lines.join('\n');
  }

  reset(): void {
    this.screen = [];
    this.cursorRow = 0;
    this.cursorCol = 0;
  }

  private writeText(text: string): void {
    while (this.cursorRow >= this.screen.length) {
      this.screen.push('');
    }

    if (text.includes('\n')) {
      const parts = text.split('\n');
      parts.forEach((part, index) => {
        if (index === 0) {
          this.writeToLine(part, this.cursorRow, this.cursorCol);
          this.cursorCol += part.length;
        } else {
          this.cursorRow += 1;
          this.cursorCol = 0;
          this.writeToLine(part, this.cursorRow, this.cursorCol);
          this.cursorCol = part.length;
        }
      });
    } else {
      this.writeToLine(text, this.cursorRow, this.cursorCol);
      this.cursorCol += text.length;
    }

    if (this.screen.length > this.maxLines) {
      const overflow = this.screen.length - this.maxLines;
      this.screen.splice(0, overflow);
      this.cursorRow = Math.max(0, this.cursorRow - overflow);
    }
  }

  private writeToLine(text: string, row: number, col: number): void {
    while (row >= this.screen.length) {
      this.screen.push('');
    }

    const lineChars = [...this.screen[row]];
    while (lineChars.length < col) {
      lineChars.push(' ');
    }

    [...text].forEach((char, index) => {
      const pos = col + index;
      if (pos < lineChars.length) {
        lineChars[pos] = char;
      } else {
        lineChars.push(char);
      }
    });

    this.screen[row] = lineChars.join('');
  }

  private processEscapeSequence(text: string): number | null {
    if (text.length === 0) {
      return null;
    }

    if (text[0] === '[') {
      let consumed = 1;
      let sequence = '[';
      let index = 1;

      while (index < text.length) {
        const char = text[index];
        sequence += char;
        consumed += 1;

        if (/[A-Za-z]/.test(char)) {
          this.processCSI(sequence);
          return consumed;
        }
        index += 1;
      }

      return consumed;
    }

    return null;
  }

  private processCSI(sequence: string): void {
    const inner = sequence.slice(1, -1);
    const command = sequence[sequence.length - 1];

    const handlers: Record<string, CSIHandler> = {
      K: (params) => this.processEraseInLine(params),
      A: (params) => this.processCursorUp(params),
      B: (params) => this.processCursorDown(params),
      C: (params) => this.processCursorForward(params),
      D: (params) => this.processCursorBackward(params),
      G: (params) => this.processCursorHorizontalAbsolute(params),
      H: (params) => this.processCursorPosition(params),
      f: (params) => this.processCursorPosition(params),
      m: () => {
        /* ignore */
      }
    };

    const handler = handlers[command];
    if (handler) {
      handler(inner);
    }
  }

  private processEraseInLine(params: string): void {
    const param = params.length === 0 ? '0' : params;

    while (this.cursorRow >= this.screen.length) {
      this.screen.push('');
    }

    const currentLine = this.screen[this.cursorRow];

    switch (param) {
      case '0':
      case '':
        if (this.cursorCol < currentLine.length) {
          this.screen[this.cursorRow] = currentLine.slice(0, this.cursorCol);
        }
        break;
      case '1':
        if (this.cursorCol < currentLine.length) {
          this.screen[this.cursorRow] = currentLine.slice(this.cursorCol);
        } else {
          this.screen[this.cursorRow] = '';
        }
        this.cursorCol = 0;
        break;
      case '2':
        this.screen[this.cursorRow] = '';
        this.cursorCol = 0;
        break;
      default:
        break;
    }
  }

  private processCursorUp(params: string): void {
    const count = parseInt(params, 10) || 1;
    this.cursorRow = Math.max(0, this.cursorRow - count);
  }

  private processCursorDown(params: string): void {
    const count = parseInt(params, 10) || 1;
    this.cursorRow += count;
  }

  private processCursorForward(params: string): void {
    const count = parseInt(params, 10) || 1;
    this.cursorCol += count;
  }

  private processCursorBackward(params: string): void {
    const count = parseInt(params, 10) || 1;
    this.cursorCol = Math.max(0, this.cursorCol - count);
  }

  private processCursorHorizontalAbsolute(params: string): void {
    const col = parseInt(params, 10) || 1;
    this.cursorCol = Math.max(0, col - 1);
  }

  private processCursorPosition(params: string): void {
    if (params.length === 0) {
      this.cursorRow = 0;
      this.cursorCol = 0;
      return;
    }

    const parts = params.split(';');
    if (parts.length === 2) {
      const row = parseInt(parts[0], 10) || 1;
      const col = parseInt(parts[1], 10) || 1;
      this.cursorRow = Math.max(0, row - 1);
      this.cursorCol = Math.max(0, col - 1);
    } else if (parts.length === 1) {
      const row = parseInt(parts[0], 10) || 1;
      this.cursorRow = Math.max(0, row - 1);
      this.cursorCol = 0;
    }
  }
}

