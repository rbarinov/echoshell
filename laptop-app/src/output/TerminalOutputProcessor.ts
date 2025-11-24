/**
 * TerminalOutputProcessor
 * -----------------------
 * Mirrors the Swift implementation that keeps track of the previously
 * processed screen output and extracts only the newly added lines.
 */

export class TerminalOutputProcessor {
  private lastProcessedScreenOutput = '';

  extractNewLines(currentOutput: string): string {
    if (this.lastProcessedScreenOutput.length === 0) {
      this.lastProcessedScreenOutput = currentOutput;
      return currentOutput;
    }

    const currentCleaned = this.removeAnsiCodes(currentOutput);
    const lastCleaned = this.removeAnsiCodes(this.lastProcessedScreenOutput);

    if (currentCleaned === lastCleaned) {
      return '';
    }

    if (currentCleaned.startsWith(lastCleaned)) {
      const newContent = currentCleaned.slice(lastCleaned.length);
      this.lastProcessedScreenOutput = currentOutput;
      return newContent.trim().length === 0 ? '' : newContent;
    }

    if (currentCleaned.endsWith(lastCleaned) && currentCleaned.length > lastCleaned.length) {
      const newContent = currentCleaned.slice(0, currentCleaned.length - lastCleaned.length);
      this.lastProcessedScreenOutput = currentOutput;
      return newContent.trim().length === 0 ? '' : newContent;
    }

    const currentLines = currentCleaned.split('\n');
    const lastLines = lastCleaned.split('\n');

    let newLinesStartIndex = 0;
    const minLength = Math.min(currentLines.length, lastLines.length);

    if (currentLines.length > lastLines.length) {
      newLinesStartIndex = lastLines.length;
    } else {
      for (let i = minLength - 1; i >= 0; i -= 1) {
        const currentLine = currentLines[i].trim();
        const lastLine = lastLines[i].trim();

        if (currentLine !== lastLine) {
          newLinesStartIndex = i;
          break;
        }
      }
    }

    if (newLinesStartIndex < currentLines.length) {
      const newLines = currentLines.slice(newLinesStartIndex);
      const result = newLines.join('\n');
      this.lastProcessedScreenOutput = currentOutput;
      return result.trim().length === 0 ? '' : result;
    }

    this.lastProcessedScreenOutput = currentOutput;
    return '';
  }

  reset(): void {
    this.lastProcessedScreenOutput = '';
  }

  private removeAnsiCodes(text: string): string {
    const pattern = /\u001B\[[0-9;]*[a-zA-Z]/g;
    return text.replace(pattern, '');
  }
}

