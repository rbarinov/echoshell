import { ChatOpenAI } from '@langchain/openai';
import { PromptTemplate } from 'langchain/prompts';
import { StructuredOutputParser } from 'langchain/output_parsers';
import { z } from 'zod';
import { exec } from 'child_process';
import { promisify } from 'util';
import os from 'os';
import type { TerminalManager } from '../terminal/TerminalManager.js';

const execAsync = promisify(exec);

interface Intent {
  type: 'terminal_command' | 'file_operation' | 'git_operation' | 'system_info' | 'complex_task' | 'terminal_management' | 'question';
  command?: string;
  details?: unknown;
  action?: 'create' | 'delete' | 'list' | 'change_directory' | 'create_cursor_agent_terminal' | 'rename_terminal' | 'manage_terminals';
  target?: string; // session ID or directory path
  terminal_type?: 'regular' | 'cursor_agent';
  name?: string; // for renaming
}

export class AIAgent {
  private llm: ChatOpenAI;
  
  constructor(apiKey: string) {
    this.llm = new ChatOpenAI({
      openAIApiKey: apiKey,
      modelName: 'gpt-4',
      temperature: 0
    });
  }
  
  async execute(command: string, sessionId: string, terminalManager: TerminalManager): Promise<string> {
    console.log(`🤖 AI Agent analyzing command: ${command}`);
    
    // Classify intent
    const intent = await this.classifyIntent(command);
    
    console.log(`🎯 Intent: ${intent.type}`);
    
    // Route to appropriate handler
    switch (intent.type) {
      case 'terminal_command':
        return this.executeTerminalCommand(intent.command || '', sessionId, terminalManager);
      
      case 'file_operation':
        return this.handleFileOperation(intent);
      
      case 'git_operation':
        return this.handleGitOperation(intent);
      
      case 'system_info':
        return this.handleSystemInfo(intent);
      
      case 'complex_task':
        return this.handleComplexTask(command, sessionId, terminalManager);
      
      case 'terminal_management':
        return this.handleTerminalManagement(intent, sessionId, terminalManager);
      
      case 'question':
        return this.handleQuestion(command, sessionId, terminalManager);
      
      default:
        return `I understand you want to: ${command}\n\nHowever, I'm not sure how to execute this. Can you rephrase?`;
    }
  }

  private async classifyIntent(command: string): Promise<Intent> {
    const parser = StructuredOutputParser.fromZodSchema(
      z.object({
        type: z.enum(['terminal_command', 'file_operation', 'git_operation', 'system_info', 'complex_task', 'terminal_management', 'question']),
        command: z.string().optional(),
        details: z.any().optional(),
        action: z.enum(['create', 'delete', 'list', 'change_directory', 'create_cursor_agent_terminal', 'rename_terminal', 'manage_terminals']).optional(),
        target: z.string().optional(),
        terminal_type: z.enum(['regular', 'cursor_agent']).optional(),
        name: z.string().optional()
      })
    );
    
    const prompt = PromptTemplate.fromTemplate(`
You are an AI assistant that classifies user commands for a terminal management system.

Classify this command into one of these categories:
- terminal_command: Simple shell commands (ls, cd, npm install, etc.)
- file_operation: File/directory operations (create, read, delete files)
- git_operation: Git commands (clone, commit, push, status, etc.)
- system_info: System information queries (disk usage, processes, etc.)
- complex_task: Multi-step tasks requiring planning
- terminal_management: Commands to create/delete/list terminal sessions or change working directory
- question: General questions that need answers (not commands to execute)

For terminal_management, also specify:
- action: 'create' (create regular terminal), 'create_cursor_agent_terminal' (create Cursor Agent terminal), 'delete' (delete terminal), 'list' (list terminals), 'change_directory' (change terminal working directory), 'rename_terminal' (rename terminal), 'manage_terminals' (bulk operations)
- target: session ID (for delete/rename) or directory path (for change_directory/create)
- terminal_type: 'regular' or 'cursor_agent' (for create actions)
- name: new name for terminal (for rename_terminal action)

Examples:
- "create a new terminal" -> type: terminal_management, action: create, terminal_type: regular
- "create a Cursor Agent terminal" -> type: terminal_management, action: create_cursor_agent_terminal, terminal_type: cursor_agent
- "create a Cursor Agent terminal in /Users/me/projects" -> type: terminal_management, action: create_cursor_agent_terminal, terminal_type: cursor_agent, target: /Users/me/projects
- "delete terminal session-123" -> type: terminal_management, action: delete, target: session-123
- "rename terminal session-123 to dev" -> type: terminal_management, action: rename_terminal, target: session-123, name: dev
- "list all terminals" -> type: terminal_management, action: list
- "go to /Users/me/projects" -> type: terminal_management, action: change_directory, target: /Users/me/projects
- "what is the current directory?" -> type: question
- "how do I install npm?" -> type: question

User command: {command}

{format_instructions}
`);
    
    const input = await prompt.format({
      command,
      format_instructions: parser.getFormatInstructions()
    });
    
    const response = await this.llm.invoke(input);
    const parsed = await parser.parse(response.content as string);
    return parsed as Intent;
  }
  
  private async executeTerminalCommand(command: string, sessionId: string, terminalManager: TerminalManager): Promise<string> {
    try {
      console.log(`⚡ Executing: ${command}`);
      const output = await terminalManager.executeCommand(sessionId, command || '');
      return `Command executed successfully:\n\n${output}`;
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return `Error executing command: ${errorMessage}`;
    }
  }
  
  private async handleFileOperation(intent: Intent): Promise<string> {
    // Simplified file operations
    return `File operation requested. This would handle: ${JSON.stringify(intent)}`;
  }
  
  private async handleGitOperation(intent: Intent): Promise<string> {
    try {
      // Extract git command from intent
      const details = intent.details as { command?: string } | undefined;
      const gitCommand = intent.command || details?.command || 'git status';
      
      console.log(`🔱 Git operation: ${gitCommand}`);
      
      const { stdout, stderr } = await execAsync(gitCommand);
      return stdout || stderr || 'Git command completed';
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return `Git error: ${errorMessage}`;
    }
  }
  
  private async handleSystemInfo(intent: Intent): Promise<string> {
    try {
      const info = {
        platform: process.platform,
        arch: process.arch,
        nodeVersion: process.version,
        memory: {
          total: Math.round(os.totalmem() / 1024 / 1024 / 1024) + ' GB',
          free: Math.round(os.freemem() / 1024 / 1024 / 1024) + ' GB'
        },
        uptime: Math.round(os.uptime() / 60) + ' minutes'
      };
      
      return `System Information:\n${JSON.stringify(info, null, 2)}`;
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return `Error getting system info: ${errorMessage}`;
    }
  }
  
  private async handleComplexTask(command: string, sessionId: string, terminalManager: TerminalManager): Promise<string> {
    // For complex tasks, break down into steps
    const prompt = `
You are a helpful AI assistant. The user wants to: ${command}

Break this down into specific terminal commands that can be executed step by step.
Provide the commands as a JSON array.

Example:
["git clone https://github.com/user/repo", "cd repo", "npm install"]
`;
    
    try {
      const response = await this.llm.invoke(prompt);
      const content = response.content as string;
      
      // Try to extract commands
      const match = content.match(/\[.*\]/s);
      if (match) {
        const commands = JSON.parse(match[0]);
        let results = '';
        
        for (const cmd of commands) {
          console.log(`⚡ Step: ${cmd}`);
          const output = await this.executeTerminalCommand(cmd, sessionId, terminalManager);
          results += `\n$ ${cmd}\n${output}\n`;
        }
        
        return `Multi-step task completed:\n${results}`;
      }
      
      return `Task breakdown:\n${content}`;
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return `Error handling complex task: ${errorMessage}`;
    }
  }
  
  private async handleTerminalManagement(intent: Intent, currentSessionId: string, terminalManager: TerminalManager): Promise<string> {
    const action = intent.action;
    
    try {
      switch (action) {
        case 'create': {
          const workingDir = intent.target || process.env.HOME || os.homedir();
          const terminalType = intent.terminal_type || 'regular';
          const name = intent.name;
          const newSession = await terminalManager.createSession(terminalType, workingDir, name);
          return `✅ Created new ${terminalType} terminal session: ${newSession.sessionId}${newSession.name ? ` (${newSession.name})` : ''}\nWorking directory: ${newSession.workingDir}`;
        }
        
        case 'create_cursor_agent_terminal': {
          const workingDir = intent.target || process.env.HOME || os.homedir();
          const name = intent.name;
          const newSession = await terminalManager.createSession('cursor_agent', workingDir, name);
          return `✅ Created new Cursor Agent terminal: ${newSession.sessionId}${newSession.name ? ` (${newSession.name})` : ''}\nWorking directory: ${newSession.workingDir}\nCursor Agent is starting automatically...`;
        }
        
        case 'delete': {
          const targetSessionId = intent.target || currentSessionId;
          if (!targetSessionId) {
            return '❌ Please specify which terminal session to delete';
          }
          
          const sessions = terminalManager.listSessions();
          if (!sessions.find(s => s.sessionId === targetSessionId)) {
            return `❌ Terminal session ${targetSessionId} not found`;
          }
          
          terminalManager.destroySession(targetSessionId);
          return `✅ Deleted terminal session: ${targetSessionId}`;
        }
        
        case 'rename_terminal': {
          const targetSessionId = intent.target || currentSessionId;
          const newName = intent.name;
          
          if (!targetSessionId) {
            return '❌ Please specify which terminal session to rename';
          }
          
          if (!newName) {
            return '❌ Please specify the new name for the terminal';
          }
          
          const sessions = terminalManager.listSessions();
          if (!sessions.find(s => s.sessionId === targetSessionId)) {
            return `❌ Terminal session ${targetSessionId} not found`;
          }
          
          terminalManager.renameSession(targetSessionId, newName);
          return `✅ Renamed terminal session ${targetSessionId} to: ${newName}`;
        }
        
        case 'list': {
          const sessions = terminalManager.listSessions();
          if (sessions.length === 0) {
            return '📂 No active terminal sessions';
          }
          
          let result = `📂 Active terminal sessions (${sessions.length}):\n\n`;
          sessions.forEach((s, index) => {
            const isCurrent = s.sessionId === currentSessionId ? ' (current)' : '';
            const typeLabel = s.terminalType === 'cursor_agent' ? ' [Cursor Agent]' : ' [Regular]';
            const nameLabel = s.name ? ` "${s.name}"` : '';
            result += `${index + 1}. ${s.sessionId}${nameLabel}${typeLabel}${isCurrent}\n   Directory: ${s.workingDir}\n\n`;
          });
          return result;
        }
        
        case 'manage_terminals': {
          // Bulk operations - parse command for multiple actions
          const sessions = terminalManager.listSessions();
          if (sessions.length === 0) {
            return '📂 No active terminal sessions to manage';
          }
          
          // For now, just return list with management options
          let result = `📂 Terminal Management\n\nActive sessions (${sessions.length}):\n\n`;
          sessions.forEach((s, index) => {
            const isCurrent = s.sessionId === currentSessionId ? ' (current)' : '';
            const typeLabel = s.terminalType === 'cursor_agent' ? ' [Cursor Agent]' : ' [Regular]';
            const nameLabel = s.name ? ` "${s.name}"` : '';
            result += `${index + 1}. ${s.sessionId}${nameLabel}${typeLabel}${isCurrent}\n`;
          });
          result += '\nYou can delete, rename, or create new terminals.';
          return result;
        }
        
        case 'change_directory': {
          const targetDir = intent.target;
          if (!targetDir) {
            return '❌ Please specify the directory path';
          }
          
          // Change directory in current session
          await terminalManager.executeCommand(currentSessionId, `cd "${targetDir}"`);
          return `✅ Changed directory to: ${targetDir}`;
        }
        
        default:
          return `❌ Unknown terminal management action: ${action}`;
      }
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return `❌ Error managing terminal: ${errorMessage}`;
    }
  }
  
  private async handleQuestion(command: string, sessionId: string, terminalManager: TerminalManager): Promise<string> {
    // Use LLM to answer questions
    const prompt = `
You are a helpful AI assistant for a terminal management system. The user asked: "${command}"

Provide a helpful answer. If the question is about terminal commands or system operations, you can provide guidance.
If you need to check something in the terminal, you can suggest commands to run.

Be concise and helpful.
`;
    
    try {
      const response = await this.llm.invoke(prompt);
      return response.content as string;
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return `❌ Error answering question: ${errorMessage}`;
    }
  }
}
