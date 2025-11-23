import { ChatOpenAI } from '@langchain/openai';
import { PromptTemplate } from 'langchain/prompts';
import { StructuredOutputParser } from 'langchain/output_parsers';
import { z } from 'zod';
import { exec } from 'child_process';
import { promisify } from 'util';
import fs from 'fs/promises';
import path from 'path';

const execAsync = promisify(exec);

export class AIAgent {
  private llm: ChatOpenAI;
  
  constructor(apiKey: string) {
    this.llm = new ChatOpenAI({
      openAIApiKey: apiKey,
      modelName: 'gpt-4',
      temperature: 0
    });
  }
  
  async execute(command: string, sessionId: string, terminalManager: any): Promise<string> {
    console.log(`🤖 AI Agent analyzing command: ${command}`);
    
    // Classify intent
    const intent = await this.classifyIntent(command);
    
    console.log(`🎯 Intent: ${intent.type}`);
    
    // Route to appropriate handler
    switch (intent.type) {
      case 'terminal_command':
        return this.executeTerminalCommand(intent.command, sessionId, terminalManager);
      
      case 'file_operation':
        return this.handleFileOperation(intent);
      
      case 'git_operation':
        return this.handleGitOperation(intent);
      
      case 'system_info':
        return this.handleSystemInfo(intent);
      
      case 'complex_task':
        return this.handleComplexTask(command, sessionId, terminalManager);
      
      default:
        return `I understand you want to: ${command}\n\nHowever, I'm not sure how to execute this. Can you rephrase?`;
    }
  }
  
  private async classifyIntent(command: string): Promise<any> {
    const parser = StructuredOutputParser.fromZodSchema(
      z.object({
        type: z.enum(['terminal_command', 'file_operation', 'git_operation', 'system_info', 'complex_task']),
        command: z.string().optional(),
        details: z.any().optional()
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

User command: {command}

{format_instructions}
`);
    
    const input = await prompt.format({
      command,
      format_instructions: parser.getFormatInstructions()
    });
    
    const response = await this.llm.invoke(input);
    return parser.parse(response.content as string);
  }
  
  private async executeTerminalCommand(command: string, sessionId: string, terminalManager: any): Promise<string> {
    try {
      console.log(`⚡ Executing: ${command}`);
      const output = await terminalManager.executeCommand(sessionId, command);
      return `Command executed successfully:\n\n${output}`;
    } catch (error: any) {
      return `Error executing command: ${error.message}`;
    }
  }
  
  private async handleFileOperation(intent: any): Promise<string> {
    // Simplified file operations
    return `File operation requested. This would handle: ${JSON.stringify(intent)}`;
  }
  
  private async handleGitOperation(intent: any): Promise<string> {
    try {
      // Extract git command from intent
      const gitCommand = intent.command || intent.details?.command || 'git status';
      
      console.log(`🔱 Git operation: ${gitCommand}`);
      
      const { stdout, stderr } = await execAsync(gitCommand);
      return stdout || stderr || 'Git command completed';
    } catch (error: any) {
      return `Git error: ${error.message}`;
    }
  }
  
  private async handleSystemInfo(intent: any): Promise<string> {
    try {
      const info = {
        platform: process.platform,
        arch: process.arch,
        nodeVersion: process.version,
        memory: {
          total: Math.round(require('os').totalmem() / 1024 / 1024 / 1024) + ' GB',
          free: Math.round(require('os').freemem() / 1024 / 1024 / 1024) + ' GB'
        },
        uptime: Math.round(require('os').uptime() / 60) + ' minutes'
      };
      
      return `System Information:\n${JSON.stringify(info, null, 2)}`;
    } catch (error: any) {
      return `Error getting system info: ${error.message}`;
    }
  }
  
  private async handleComplexTask(command: string, sessionId: string, terminalManager: any): Promise<string> {
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
    } catch (error: any) {
      return `Error handling complex task: ${error.message}`;
    }
  }
}
