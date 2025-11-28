import type { AIAgent } from '../agent/AIAgent';
import type { TerminalManager } from './TerminalManager';
import type { ChatMessage } from './types';
import { v4 as uuidv4 } from 'uuid';

/**
 * Callback types for AgentExecutor
 */
export type AgentOutputCallback = (message: ChatMessage) => void;
export type AgentCompleteCallback = (result: string) => void;

/**
 * Executes AI Agent commands (global agent mode)
 * Unlike HeadlessExecutor which uses CLI tools, this uses AIAgent directly
 */
export class AgentExecutor {
  private aiAgent: AIAgent;
  private terminalManager: TerminalManager;
  private workingDir: string;
  private outputCallbacks: Set<AgentOutputCallback> = new Set();
  private completeCallbacks: Set<AgentCompleteCallback> = new Set();
  private isRunning: boolean = false;

  constructor(
    workingDir: string,
    aiAgent: AIAgent,
    terminalManager: TerminalManager
  ) {
    this.workingDir = workingDir;
    this.aiAgent = aiAgent;
    this.terminalManager = terminalManager;
  }

  /**
   * Execute a command via AI Agent
   * @param prompt - The user prompt/command to execute
   */
  async execute(prompt: string): Promise<void> {
    if (this.isRunning) {
      console.warn(`⚠️ [AgentExecutor] Command already running, ignoring new request`);
      return;
    }

    this.isRunning = true;
    console.log(`🤖 [AgentExecutor] Executing AI Agent command: ${prompt.substring(0, 100)}${prompt.length > 100 ? '...' : ''}`);

    // Send user message
    const userMessage: ChatMessage = {
      id: uuidv4(),
      timestamp: Date.now(),
      type: 'user',
      content: prompt,
    };
    this.notifyOutput(userMessage);

    try {
      // Execute via AI Agent (no terminal session - global agent)
      const result = await this.aiAgent.execute(prompt, undefined, this.terminalManager);

      console.log(`✅ [AgentExecutor] AI Agent response: ${result.output.substring(0, 100)}${result.output.length > 100 ? '...' : ''}`);

      // Send assistant response
      const assistantMessage: ChatMessage = {
        id: uuidv4(),
        timestamp: Date.now(),
        type: 'assistant',
        content: result.output,
      };
      this.notifyOutput(assistantMessage);

      // Send completion message
      const completionMessage: ChatMessage = {
        id: uuidv4(),
        timestamp: Date.now(),
        type: 'system',
        content: 'Command completed',
        metadata: { completion: true },
      };
      this.notifyOutput(completionMessage);

      // Notify completion
      this.notifyComplete(result.output);

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      console.error(`❌ [AgentExecutor] Error executing command:`, error);

      // Send error message
      const errMsg: ChatMessage = {
        id: uuidv4(),
        timestamp: Date.now(),
        type: 'error',
        content: `Error: ${errorMessage}`,
        metadata: { errorCode: 'AGENT_ERROR' },
      };
      this.notifyOutput(errMsg);

      // Notify completion (even on error)
      this.notifyComplete(`Error: ${errorMessage}`);
    } finally {
      this.isRunning = false;
    }
  }

  /**
   * Register callback for output messages
   */
  onOutput(callback: AgentOutputCallback): void {
    this.outputCallbacks.add(callback);
  }

  /**
   * Remove output callback
   */
  offOutput(callback: AgentOutputCallback): void {
    this.outputCallbacks.delete(callback);
  }

  /**
   * Register callback for command completion
   */
  onComplete(callback: AgentCompleteCallback): void {
    this.completeCallbacks.add(callback);
  }

  /**
   * Remove completion callback
   */
  offComplete(callback: AgentCompleteCallback): void {
    this.completeCallbacks.delete(callback);
  }

  /**
   * Kill any running execution (agent commands are not cancellable in the same way)
   */
  kill(): void {
    // Agent commands run synchronously via LLM, so there's nothing to kill
    // This is here for interface compatibility with HeadlessExecutor
    console.log(`🛑 [AgentExecutor] Kill requested (no-op for agent commands)`);
  }

  /**
   * Update working directory
   */
  setWorkingDir(dir: string): void {
    this.workingDir = dir;
  }

  /**
   * Get current working directory
   */
  getWorkingDir(): string {
    return this.workingDir;
  }

  /**
   * Check if command is currently running
   */
  getIsRunning(): boolean {
    return this.isRunning;
  }

  private notifyOutput(message: ChatMessage): void {
    this.outputCallbacks.forEach(callback => {
      try {
        callback(message);
      } catch (error) {
        console.error(`❌ [AgentExecutor] Error in output callback:`, error);
      }
    });
  }

  private notifyComplete(result: string): void {
    this.completeCallbacks.forEach(callback => {
      try {
        callback(result);
      } catch (error) {
        console.error(`❌ [AgentExecutor] Error in complete callback:`, error);
      }
    });
  }
}

