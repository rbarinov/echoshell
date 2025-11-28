import type { AIAgent } from '../agent/AIAgent';
import type { TerminalManager } from './TerminalManager';
import type { ChatMessage } from './types';
import type { ChatHistoryDatabase } from '../database/ChatHistoryDatabase';
import { v4 as uuidv4 } from 'uuid';

/**
 * Callback types for AgentExecutor
 */
export type AgentOutputCallback = (message: ChatMessage) => void;
export type AgentCompleteCallback = (result: string) => void;

/**
 * Executes AI Agent commands (global agent mode)
 * Unlike HeadlessExecutor which uses CLI tools, this uses AIAgent directly
 * Maintains conversation history for context-aware responses
 */
export class AgentExecutor {
  private aiAgent: AIAgent;
  private terminalManager: TerminalManager;
  private workingDir: string;
  private sessionId: string;
  private chatHistoryDb: ChatHistoryDatabase;
  private conversationHistory: ChatMessage[] = [];
  private outputCallbacks: Set<AgentOutputCallback> = new Set();
  private completeCallbacks: Set<AgentCompleteCallback> = new Set();
  private isRunning: boolean = false;

  constructor(
    workingDir: string,
    aiAgent: AIAgent,
    terminalManager: TerminalManager,
    sessionId: string,
    chatHistoryDb: ChatHistoryDatabase
  ) {
    this.workingDir = workingDir;
    this.aiAgent = aiAgent;
    this.terminalManager = terminalManager;
    this.sessionId = sessionId;
    this.chatHistoryDb = chatHistoryDb;
    
    // Load conversation history from database
    this.loadHistory();
  }
  
  /**
   * Load conversation history from database
   */
  private loadHistory(): void {
    const history = this.chatHistoryDb.getChatHistory(this.sessionId);
    if (history && history.messages.length > 0) {
      this.conversationHistory = history.messages;
      console.log(`📚 [AgentExecutor] Loaded ${this.conversationHistory.length} messages from history`);
    }
  }
  
  /**
   * Reset conversation context (clear history)
   */
  async resetContext(): Promise<void> {
    this.conversationHistory = [];
    this.chatHistoryDb.clearHistory(this.sessionId);
    console.log(`🔄 [AgentExecutor] Context reset for session ${this.sessionId}`);
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

    // Create and save user message
    const userMessage: ChatMessage = {
      id: uuidv4(),
      timestamp: Date.now(),
      type: 'user',
      content: prompt,
    };
    
    // Add to conversation history
    this.conversationHistory.push(userMessage);
    
    // Persist to database
    this.chatHistoryDb.addMessage(this.sessionId, userMessage);
    
    // Notify output
    this.notifyOutput(userMessage);

    try {
      // Execute via AI Agent with context
      // For now, use execute() - will be enhanced with executeWithContext() later
      const result = await this.aiAgent.execute(prompt, undefined, this.terminalManager);

      console.log(`✅ [AgentExecutor] AI Agent response: ${result.output.substring(0, 100)}${result.output.length > 100 ? '...' : ''}`);

      // Create and save assistant message
      const assistantMessage: ChatMessage = {
        id: uuidv4(),
        timestamp: Date.now(),
        type: 'assistant',
        content: result.output,
      };
      
      // Add to conversation history
      this.conversationHistory.push(assistantMessage);
      
      // Persist to database
      this.chatHistoryDb.addMessage(this.sessionId, assistantMessage);
      
      // Notify output
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

      // Create and save error message
      const errMsg: ChatMessage = {
        id: uuidv4(),
        timestamp: Date.now(),
        type: 'error',
        content: `Error: ${errorMessage}`,
        metadata: { errorCode: 'AGENT_ERROR' },
      };
      
      // Add to conversation history
      this.conversationHistory.push(errMsg);
      
      // Persist to database
      this.chatHistoryDb.addMessage(this.sessionId, errMsg);
      
      // Notify output
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

