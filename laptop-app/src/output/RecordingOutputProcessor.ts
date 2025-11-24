export interface RecordingProcessResult {
  fullText: string;
  delta: string;
  rawFiltered: string;
}

const BOX_CHARS = new Set(['┌', '┐', '└', '┘', '│', '─']);

export class RecordingOutputProcessor {
  private lastOutput = '';
  private lastSentCommand = '';
  private lastDelta = '';

  setLastCommand(command: string): void {
    if (!command) {
      return;
    }
    this.lastSentCommand = command.trim();
  }

  reset(): void {
    this.lastOutput = '';
    this.lastSentCommand = '';
    this.lastDelta = '';
  }

  processOutput(output: string, screenOutput: string): RecordingProcessResult | null {
    const trimmedOutput = output.trim();

    if (trimmedOutput.length === 0) {
      return null;
    }

    let filteredOutput = this.filterIntermediateMessages(trimmedOutput);

    if (filteredOutput.trim().length === 0) {
      // Fallback to screen output (fully rendered) if incremental output was empty
      filteredOutput = this.filterIntermediateMessages(screenOutput);
    }

    if (filteredOutput.trim().length === 0) {
      return null;
    }

    const result = this.extractCommandResult(filteredOutput);
    let textToAppend = '';

    if (result.trim().length > 0) {
      textToAppend = result;
    } else {
      // Keep filtered output as fallback (after removing any residual ANSI codes)
      const cleaned = this.removeAnsiCodes(filteredOutput);
      if (cleaned.trim().length > 0) {
        textToAppend = cleaned;
      }
    }

    if (textToAppend.trim().length === 0) {
      return null;
    }

    const delta = this.appendToTerminalOutput(textToAppend);
    if (!delta) {
      return null;
    }

    return {
      fullText: this.lastOutput,
      delta,
      rawFiltered: filteredOutput
    };
  }

  private appendToTerminalOutput(newText: string): string {
    const trimmedNew = newText.trim();
    if (trimmedNew.length === 0) {
      return '';
    }

    if (this.lastDelta === trimmedNew) {
      return '';
    }

    if (this.lastOutput.length === 0) {
      this.lastOutput = trimmedNew;
      return trimmedNew;
    }

    const currentOutput = this.lastOutput.trim();

    if (currentOutput === trimmedNew) {
      return '';
    }

    if (currentOutput.endsWith(trimmedNew)) {
      const suffixLength = trimmedNew.length;
      const currentLength = currentOutput.length;
      if (suffixLength > currentLength * 0.9) {
        return '';
      }
    }

    if (currentOutput.includes(trimmedNew)) {
      const newLength = trimmedNew.length;
      const currentLength = currentOutput.length;
      if (newLength > currentLength * 0.95) {
        return '';
      }
    }

    const separator = /[.!?]$/.test(currentOutput) ? ' ' : '\n\n';
    const appended = currentOutput + separator + trimmedNew;
    const limited = appended.length > 10000 ? appended.slice(-10000) : appended;
    const delta = trimmedNew;

    this.lastOutput = limited;
    this.lastDelta = delta;
    return delta;
  }

  private extractCommandResult(output: string): string {
    const lines = output.split(/\r?\n/);
    const codeBoxes: string[] = [];
    const resultLines: string[] = [];
    let inBox = false;
    let currentBox: string[] = [];

    lines.forEach((line) => {
      const trimmed = line.trim();

      if (trimmed.includes('┌') && !inBox) {
        inBox = true;
        currentBox = [];
        return;
      }

      if (trimmed.includes('└') && inBox) {
        inBox = false;
        const boxContent = currentBox
          .map((boxLine) => this.cleanBoxLine(boxLine))
          .filter((content) => content.length > 0);

        if (boxContent.length > 0) {
          const boxText = boxContent.join(' ');
          if (this.shouldKeepBox(boxText)) {
            codeBoxes.push(boxContent.join('\n'));
          }
        }
        currentBox = [];
        return;
      }

      if (inBox) {
        if (![...trimmed].every((char) => BOX_CHARS.has(char) || /\s/.test(char))) {
          currentBox.push(line);
        }
        return;
      }

      if (trimmed.length === 0) {
        return;
      }

      if (this.shouldSkipLine(trimmed)) {
        return;
      }

      const cleanedLine = this.removeAnsiCodes(this.removeDimText(line)).trim();
      if (cleanedLine.length >= 3) {
        resultLines.push(cleanedLine);
      }
    });

    const allResults: string[] = [];
    if (codeBoxes.length > 0) {
      allResults.push(...codeBoxes);
    }

    const meaningfulLines = resultLines.filter((line) => line.trim().length >= 5);
    if (meaningfulLines.length > 0) {
      allResults.push(...meaningfulLines);
    }

    return allResults.length > 0 ? allResults.join('\n\n') : '';
  }

  private shouldKeepBox(boxText: string): boolean {
    if (boxText.toLowerCase().includes('add a follow-up')) {
      return false;
    }

    if (this.lastSentCommand.length > 0) {
      const normalizedCommand = this.lastSentCommand.trim().toLowerCase();
      const normalizedBox = boxText.toLowerCase();
      if (
        normalizedBox.includes(normalizedCommand) ||
        normalizedCommand.includes(normalizedBox)
      ) {
        return false;
      }
    }

    return true;
  }

  private shouldSkipLine(trimmed: string): boolean {
    const uiStatusPattern = /·\s*\d+\.?\d*%/;
    if (uiStatusPattern.test(trimmed)) {
      return true;
    }

    const uiPhrases = [
      '/ commands',
      '@ files',
      '! shell',
      'review edits',
      'add a follow-up',
      'follow-up',
      'ctrl+r'
    ];

    if (uiPhrases.some((phrase) => trimmed.toLowerCase().includes(phrase.toLowerCase()))) {
      return true;
    }

    if (trimmed === '~' || trimmed === '%') {
      return true;
    }

    if (trimmed.startsWith('⬢') || trimmed.startsWith('⬡')) {
      return true;
    }

    if (trimmed.startsWith('│') || trimmed.startsWith('┌') || trimmed.startsWith('└')) {
      return true;
    }

    if (/^\s*[~→].*%$/.test(trimmed)) {
      return true;
    }

    if (/tokens/i.test(trimmed)) {
      return true;
    }

    if (
      trimmed.length < 50 &&
      /(reading|editing|generating)/i.test(trimmed) &&
      (trimmed.includes('⬡') || trimmed.includes('⬢'))
    ) {
      return true;
    }

    if (trimmed.startsWith(']') || trimmed.startsWith('➜')) {
      return true;
    }

    if (/cursor-agent>/i.test(trimmed)) {
      return true;
    }

    const lower = trimmed.toLowerCase();
    const noisePhrases = [
      'add a follow-up',
      'ctrl+c to stop',
      'starting...',
      'cursor agent',
      'composer ',
      'plan, search, build anything',
      'commands · @ files · ! shell',
      'cwd is not a git repository',
      'cursor rules and ignore files don\'t apply',
      'cursor-agent]1;cursor-agent',
      'roman@romans-macbook-pro'
    ];

    if (noisePhrases.some((phrase) => lower.includes(phrase))) {
      return true;
    }

    if (/^\(cwd is not a git repository.*apply\)$/i.test(trimmed)) {
      return true;
    }

    if (this.lastSentCommand.length > 0) {
      const normalizedCommand = this.lastSentCommand.toLowerCase();
      const normalizedLine = trimmed.toLowerCase();
      if (normalizedLine === normalizedCommand) {
        return true;
      }
      if (
        trimmed.length <= normalizedCommand.length + 5 &&
        normalizedLine.includes(normalizedCommand)
      ) {
        return true;
      }
    }

    return false;
  }

  private cleanBoxLine(line: string): string {
    let cleaned = line.trim();
    if (cleaned.startsWith('│')) {
      cleaned = cleaned.slice(1).trimStart();
    }
    if (cleaned.endsWith('│')) {
      cleaned = cleaned.slice(0, -1).trimEnd();
    }
    cleaned = this.removeAnsiCodes(cleaned);
    cleaned = this.removeDimText(cleaned);
    return cleaned.trim();
  }

  private filterIntermediateMessages(output: string): string {
    const lines = output.split(/\r?\n/);
    const meaningfulLines: string[] = [];

    lines.forEach((line) => {
      const withoutDim = this.removeDimText(line);
      const cleanedLine = this.removeAnsiCodes(withoutDim);
      const trimmed = cleanedLine.trim();

      if (trimmed.length === 0) {
        return;
      }

      if ([...trimmed].some((char) => BOX_CHARS.has(char))) {
        return;
      }

      if (this.shouldSkipLine(trimmed)) {
        return;
      }

      meaningfulLines.push(cleanedLine.trimEnd());
    });

    return meaningfulLines.join('\n');
  }

  private removeAnsiCodes(text: string): string {
    let result = text.replace(/\u001B\[[0-9;?]*[A-Za-z]/g, '');
    result = result.replace(/\u001B\][^\u0007]*(?:\u0007|\u001B\\)/g, '');
    result = result.replace(/\u0007/g, '');
    return result;
  }

  private removeDimText(text: string): string {
    let result = text;

    const dimPattern = /\u001b\[2[0-9;]*m.*?\u001b\[[0-9;]*m/gs;
    result = result.replace(dimPattern, '');

    const dimToEndPattern = /\u001b\[2[0-9;]*m[^\n]*/g;
    result = result.replace(dimToEndPattern, '');

    const standaloneDimPattern = /\u001b\[2[0-9;]*m/g;
    result = result.replace(standaloneDimPattern, '');

    return result;
  }
}

