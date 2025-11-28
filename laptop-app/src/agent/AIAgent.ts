import { PromptTemplate } from '@langchain/core/prompts';
import { StructuredOutputParser } from '@langchain/core/output_parsers';
import { z } from 'zod';
import { exec } from 'child_process';
import { promisify } from 'util';
import os from 'os';
import type { TerminalManager } from '../terminal/TerminalManager.js';
import type { LLMProvider } from './LLMProvider.js';
import type { WorkspaceManager } from '../workspace/WorkspaceManager.js';
import type { WorktreeManager } from '../workspace/WorktreeManager.js';
import { normalizeWorkspaceName, normalizeRepositoryName, normalizeBranchName, normalizeTerminalName } from '../workspace/nameNormalizer.js';

const execAsync = promisify(exec);

interface Intent {
  type: 'terminal_command' | 'file_operation' | 'git_operation' | 'system_info' | 'complex_task' | 'terminal_management' | 'workspace_operation' | 'worktree_operation' | 'question';
  command?: string;
  details?: unknown;
  action?: 'create' | 'delete' | 'list' | 'change_directory' | 'create_cursor_agent_terminal' | 'rename_terminal' | 'manage_terminals' | 'create_workspace' | 'remove_workspace' | 'list_workspaces' | 'clone_repository' | 'list_repositories' | 'create_project' | 'list_projects' | 'create_terminal_in_project' | 'create_worktree' | 'remove_worktree' | 'list_worktrees' | 'create_terminal_in_worktree';
  target?: string; // session ID, directory path, workspace name, repo name, or worktree name
  terminal_type?: 'regular' | 'cursor' | 'claude';
  name?: string; // for renaming, workspace name, repo name, project name, or worktree name
  workspace?: string; // workspace name
  repo?: string; // repository name
  project?: string; // project name
  branch_or_feature?: string; // branch or feature name for worktree
}

export class AIAgent {
  private llmProvider: LLMProvider;
  private workspaceManager?: WorkspaceManager;
  private worktreeManager?: WorktreeManager;

  constructor(llmProvider: LLMProvider) {
    this.llmProvider = llmProvider;
  }

  setWorkspaceManager(workspaceManager: WorkspaceManager): void {
    this.workspaceManager = workspaceManager;
  }

  setWorktreeManager(worktreeManager: WorktreeManager): void {
    this.worktreeManager = worktreeManager;
  }
  
  /**
   * Clear any stored context (for now, this is a no-op as AIAgent doesn't maintain state)
   * In the future, this could clear conversation history if we implement that
   */
  clearContext(): void {
    console.log('🔄 AIAgent: Context cleared');
    // Currently AIAgent doesn't maintain conversation state
    // Future: clear conversation history here
  }
  
  async execute(command: string, sessionId?: string, terminalManager?: TerminalManager): Promise<{ output: string; sessionId?: string }> {
    console.log(`🤖 AI Agent analyzing command: ${command}${sessionId ? ` (session: ${sessionId})` : ' (no session)'}`);
    
    // Classify intent
    const intent = await this.classifyIntent(command);
    
    console.log(`🎯 Intent: ${intent.type}`);
    
    // For terminal commands, we need a session. Create one if not provided.
    let actualSessionId = sessionId;
    let actualTerminalManager = terminalManager;
    
    if ((intent.type === 'terminal_command' || intent.type === 'complex_task' || intent.type === 'file_operation') && !sessionId && terminalManager) {
      // Auto-create a persistent session for terminal operations
      // Use WORK_ROOT_PATH env var as default, or let createSession use its default
      console.log(`📟 Auto-creating persistent session for terminal command...`);
      const defaultWorkingDir = process.env.WORK_ROOT_PATH || undefined;
      const newSession = await terminalManager.createSession('regular', defaultWorkingDir, `agent-${Date.now()}`);
      actualSessionId = newSession.sessionId;
      actualTerminalManager = terminalManager;
      console.log(`✅ Created persistent session: ${actualSessionId}`);
    }
    
    // Route to appropriate handler
    let output: string;
    switch (intent.type) {
      case 'terminal_command':
        if (!actualTerminalManager || !actualSessionId) {
          output = 'Terminal command requires a terminal session. Please create a terminal first.';
        } else {
          output = await this.executeTerminalCommand(intent.command || '', actualSessionId, actualTerminalManager);
        }
        break;
      
      case 'file_operation':
        if (!actualTerminalManager || !actualSessionId) {
          output = await this.handleFileOperation(intent);
        } else {
          // File operations can use terminal if available
          output = await this.executeTerminalCommand(intent.command || '', actualSessionId, actualTerminalManager);
        }
        break;
      
      case 'git_operation':
        output = await this.handleGitOperation(intent);
        break;
      
      case 'system_info':
        output = await this.handleSystemInfo(intent);
        break;
      
      case 'complex_task':
        if (!actualTerminalManager || !actualSessionId) {
          output = 'Complex task requires a terminal session. Please create a terminal first.';
        } else {
          output = await this.handleComplexTask(command, actualSessionId, actualTerminalManager);
        }
        break;
      
      case 'terminal_management':
        if (!actualTerminalManager) {
          output = 'Terminal management requires terminal manager.';
        } else {
          output = await this.handleTerminalManagement(intent, actualSessionId || 'default', actualTerminalManager);
        }
        break;
      
      case 'question':
        output = await this.handleQuestion(command, actualSessionId || 'default', actualTerminalManager);
        break;
      
      case 'workspace_operation':
        output = await this.handleWorkspaceOperation(intent, actualSessionId || 'default', actualTerminalManager);
        break;
      
      case 'worktree_operation':
        output = await this.handleWorktreeOperation(intent, actualSessionId || 'default', actualTerminalManager);
        break;
      
      default:
        output = `I understand you want to: ${command}\n\nHowever, I'm not sure how to execute this. Can you rephrase?`;
    }
    
    return {
      output,
      sessionId: actualSessionId
    };
  }

  private async classifyIntent(command: string): Promise<Intent> {
    // Use a simpler schema to avoid TypeScript deep instantiation issues
    const schema = z.object({
        type: z.enum(['terminal_command', 'file_operation', 'git_operation', 'system_info', 'complex_task', 'terminal_management', 'workspace_operation', 'worktree_operation', 'question']),
        command: z.string().optional(),
        details: z.any().optional(),
        action: z.enum(['create', 'delete', 'list', 'change_directory', 'create_cursor_agent_terminal', 'rename_terminal', 'manage_terminals', 'create_workspace', 'remove_workspace', 'list_workspaces', 'clone_repository', 'list_repositories', 'create_worktree', 'remove_worktree', 'list_worktrees', 'create_terminal_in_worktree']).optional(),
        target: z.string().optional(),
        terminal_type: z.enum(['regular', 'cursor', 'claude']).optional(),
        name: z.string().optional(),
        workspace: z.string().optional(),
        repo: z.string().optional(),
        branch_or_feature: z.string().optional()
      }) as z.ZodType<Intent>;
    
    // @ts-ignore - Type instantiation is excessively deep, but works at runtime
    const parser = StructuredOutputParser.fromZodSchema(schema);
    
    const prompt = PromptTemplate.fromTemplate(`
You are a Terminal Management Specialist - a focused AI assistant that classifies user commands for a terminal management system.

PRIMARY ROLE: Classify commands related to terminal creation/management, workspace organization, repository management, and git worktrees.

LANGUAGE: Always respond in the same language the user is using. Match the language automatically based on the user's input.

NAME NORMALIZATION: All names (workspaces, repositories, branches, worktrees, terminals) will be automatically normalized to kebab-case format (lowercase, Latin characters, hyphens only). Extract names as provided by the user - normalization happens in code.

SCOPE LIMITATION: If a command is clearly unrelated to terminal management, workspace operations, or git worktrees, classify it as 'question' with action 'out_of_scope'. Examples of out-of-scope: general knowledge questions, code writing requests, explanations of unrelated concepts.

Classify this command into one of these categories:
- terminal_command: Simple shell commands (ls, cd, npm install, etc.) - ONLY if user explicitly wants to execute a command
- file_operation: File/directory operations (create, read, delete files) - ONLY if user explicitly wants file operations
- git_operation: Git commands (clone, commit, push, status, etc.) - ONLY if user explicitly wants git operations
- system_info: System information queries (disk usage, processes, etc.)
- complex_task: Multi-step tasks requiring planning
- terminal_management: Commands to create/delete/list terminal sessions or change working directory
- workspace_operation: Commands to create/remove/list workspaces, clone repositories, or create/list projects in workspaces
- worktree_operation: Commands to create/remove/list git worktrees
- question: General questions that need answers (not commands to execute)

For terminal_management, also specify:
- action: 'create' (create regular terminal), 'create_cursor_agent_terminal' (create Cursor Agent terminal), 'delete' (delete terminal), 'list' (list terminals), 'change_directory' (change terminal working directory), 'rename_terminal' (rename terminal), 'manage_terminals' (bulk operations)
- target: session ID (for delete/rename) or directory path (for change_directory/create)
- terminal_type: 'regular', 'cursor', or 'claude' (for create actions)
- name: new name for terminal (for rename_terminal action)

Examples:
- "create a new terminal" -> type: terminal_management, action: create, terminal_type: regular
- "create a Cursor Agent terminal" -> type: terminal_management, action: create_cursor_agent_terminal, terminal_type: cursor
- "create a Cursor Agent terminal in /Users/me/projects" -> type: terminal_management, action: create_cursor_agent_terminal, terminal_type: cursor, target: /Users/me/projects
- "delete terminal session-123" -> type: terminal_management, action: delete, target: session-123
- "rename terminal session-123 to dev" -> type: terminal_management, action: rename_terminal, target: session-123, name: dev
- "list all terminals" -> type: terminal_management, action: list
- "go to /Users/me/projects" -> type: terminal_management, action: change_directory, target: /Users/me/projects
- "create workspace my-workspace" -> type: workspace_operation, action: create_workspace, name: my-workspace
- "clone https://github.com/user/repo into workspace my-workspace" -> type: workspace_operation, action: clone_repository, workspace: my-workspace, target: https://github.com/user/repo
- "create project Example Project in workspace my-workspace" -> type: workspace_operation, action: create_project, workspace: my-workspace, name: Example Project
- "list projects in workspace my-workspace" -> type: workspace_operation, action: list_projects, workspace: my-workspace
- "list workspaces" -> type: workspace_operation, action: list_workspaces
- "create worktree feature-auth for repo myrepo in workspace my-workspace" -> type: worktree_operation, action: create_worktree, workspace: my-workspace, repo: myrepo, branch_or_feature: feature-auth
- "list worktrees for repo myrepo in workspace my-workspace" -> type: worktree_operation, action: list_worktrees, workspace: my-workspace, repo: myrepo
- "create cursor agent terminal in worktree feature-auth" -> type: worktree_operation, action: create_terminal_in_worktree, name: feature-auth, terminal_type: cursor
- "create terminal in project Example Project in workspace my-workspace" -> type: workspace_operation, action: create_terminal_in_project, workspace: my-workspace, name: Example Project
- "what is the current directory?" -> type: question
- "how do I install npm?" -> type: question

User command: {command}

{format_instructions}
`);
    
    // @ts-ignore - Type instantiation is excessively deep, but works at runtime
    const input = await prompt.format({
      command,
      // @ts-ignore - Type instantiation is excessively deep, but works at runtime
      format_instructions: parser.getFormatInstructions()
    });
    
    const llm = this.llmProvider.getLLM();
    const response = await llm.invoke(input);
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
    // Route file operations to terminal commands
    const command = intent.command || JSON.stringify(intent.details || {});
    return `File operation: ${command}\n\nPlease use terminal commands for file operations (e.g., "create file.txt", "read file.txt", "delete file.txt")`;
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
  
  private async handleSystemInfo(_intent: Intent): Promise<string> {
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
      const llm = this.llmProvider.getLLM();
      const response = await llm.invoke(prompt);
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
          // Use target directory, or fallback to WORK_ROOT_PATH env var, or HOME, or system homedir
          const workingDir = intent.target || process.env.WORK_ROOT_PATH || process.env.HOME || os.homedir();
          const terminalType = intent.terminal_type || 'regular';
          const name = intent.name ? normalizeTerminalName(intent.name) : undefined;
          const newSession = await terminalManager.createSession(terminalType, workingDir, name);
          return `✅ Created ${terminalType} terminal: ${newSession.sessionId}${newSession.name ? ` (${newSession.name})` : ''}`;
        }
        
        case 'create_cursor_agent_terminal': {
          // Use target directory, or fallback to WORK_ROOT_PATH env var, or HOME, or system homedir
          const workingDir = intent.target || process.env.WORK_ROOT_PATH || process.env.HOME || os.homedir();
          const name = intent.name ? normalizeTerminalName(intent.name) : undefined;
          const newSession = await terminalManager.createSession('cursor', workingDir, name);
          return `✅ Created cursor agent terminal: ${newSession.sessionId}${newSession.name ? ` (${newSession.name})` : ''}`;
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
          
          await terminalManager.destroySession(targetSessionId);
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
          
          // Normalize terminal name to kebab-case
          const normalizedName = normalizeTerminalName(newName);
          terminalManager.renameSession(targetSessionId, normalizedName);
          return `✅ Renamed terminal session ${targetSessionId} to: ${normalizedName}`;
        }
        
        case 'list': {
          const sessions = terminalManager.listSessions();
          if (sessions.length === 0) {
            return 'No active terminals';
          }
          
          const sessionList = sessions.map((s, index) => {
            const typeLabel = s.terminalType === 'cursor' ? 'cursor' : s.terminalType === 'claude' ? 'claude' : 'regular';
            const nameLabel = s.name || s.sessionId;
            return `${index + 1}. ${nameLabel} (${typeLabel})`;
          }).join('. ');
          
          return `${sessions.length} terminals: ${sessionList}`;
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
            const typeLabel = s.terminalType === 'cursor' ? ' [Cursor]' : s.terminalType === 'claude' ? ' [Claude]' : ' [Regular]';
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
  
  private async handleQuestion(command: string, _sessionId: string, _terminalManager?: TerminalManager): Promise<string> {
    // Use LLM to answer questions with scope limitation
    const prompt = `
You are a Terminal Management Specialist - a focused AI assistant for a terminal management system.

PRIMARY ROLE: Help with terminal management, workspace organization, repository management, and git worktrees.

LANGUAGE: Always respond in the same language the user is using. If the user asks in Russian, respond in Russian. If the user asks in English, respond in English. Match the language automatically based on the user's input.

RESPONSE STYLE:
- Always respond as briefly as possible without losing essential information
- Use concise, action-oriented language
- Format responses for voice output (short sentences, clear structure)

SCOPE:
You can help with:
- Creating/managing terminals (regular, cursor, claude)
- Creating/managing workspaces (organizations/clients)
- Cloning/searching repositories
- Creating/managing git worktrees
- Basic system information queries related to terminal management

You CANNOT help with:
- General knowledge questions (weather, science, history, etc.)
- Writing code or scripts
- Explaining concepts unrelated to terminal management
- Any task outside your core responsibilities

REJECTION FORMAT:
If asked about something outside your scope, respond briefly in the same language as the user:
- English: "I can only help with terminal management, workspace organization, and git worktrees."
- Russian: "Я могу помочь только с управлением терминалами, организацией workspace и git worktrees."

The user asked: "${command}"

Detect the user's language and respond in the same language. Provide a brief, helpful answer if it's within your scope. If it's outside your scope, reject it using the appropriate language format above.
`;
    
    try {
      const llm = this.llmProvider.getLLM();
      const response = await llm.invoke(prompt);
      const content = response.content as string;
      
      // Ensure response is brief (limit to 200 characters for voice output)
      if (content.length > 200) {
        // Try to extract the first sentence or key point
        const firstSentence = content.split(/[.!?]/)[0];
        if (firstSentence.length <= 200) {
          return firstSentence;
        }
        return content.substring(0, 197) + '...';
      }
      
      return content;
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return `❌ Error: ${errorMessage}`;
    }
  }

  private async handleWorkspaceOperation(intent: Intent, _sessionId: string, _terminalManager?: TerminalManager): Promise<string> {
    if (!this.workspaceManager) {
      return '❌ Workspace manager is not available';
    }

    const action = intent.action;

    try {
      switch (action) {
        case 'create_workspace': {
          const workspaceName = intent.name || intent.target;
          if (!workspaceName) {
            return '❌ Please specify workspace name';
          }
          // Normalize workspace name to kebab-case
          const normalizedName = normalizeWorkspaceName(workspaceName);
          const workspace = await this.workspaceManager.createWorkspace(normalizedName);
          return `✅ Created workspace: ${workspace.name}`;
        }

        case 'remove_workspace': {
          const workspaceName = intent.target || intent.name;
          if (!workspaceName) {
            return '❌ Please specify workspace name to remove';
          }
          // Normalize workspace name to kebab-case
          const normalizedName = normalizeWorkspaceName(workspaceName);
          await this.workspaceManager.removeWorkspace(normalizedName);
          return `✅ Removed workspace: ${normalizedName}`;
        }

        case 'list_workspaces': {
          const workspaces = await this.workspaceManager.listWorkspaces();
          if (workspaces.length === 0) {
            return 'No workspaces found';
          }
          const workspaceList = workspaces.map((w, index) => `${index + 1}. ${w.name}`).join('. ');
          return `${workspaces.length} workspaces: ${workspaceList}`;
        }

        case 'clone_repository': {
          const workspace = intent.workspace || intent.target;
          const repoUrl = intent.target || intent.command;
          if (!workspace) {
            return '❌ Please specify workspace name';
          }
          if (!repoUrl) {
            return '❌ Please specify repository URL';
          }
          // Normalize workspace and repository names to kebab-case
          const normalizedWorkspace = normalizeWorkspaceName(workspace);
          const normalizedRepoName = intent.name ? normalizeRepositoryName(intent.name) : undefined;
          const repo = await this.workspaceManager.cloneRepository(normalizedWorkspace, repoUrl, normalizedRepoName);
          return `✅ Cloned repository: ${repo.name}`;
        }

        case 'list_repositories': {
          const workspace = intent.workspace || intent.target;
          if (!workspace) {
            return '❌ Please specify workspace name';
          }
          // Normalize workspace name to kebab-case
          const normalizedWorkspace = normalizeWorkspaceName(workspace);
          const repos = await this.workspaceManager.listRepositories(normalizedWorkspace);
          if (repos.length === 0) {
            return `No repositories in workspace "${normalizedWorkspace}"`;
          }
          const repoList = repos.map((r, index) => `${index + 1}. ${r.name}`).join('. ');
          return `${repos.length} repositories: ${repoList}`;
        }

        case 'create_project': {
          const workspace = intent.workspace || intent.target;
          const projectName = intent.name || intent.project;
          if (!workspace) {
            return '❌ Please specify workspace name';
          }
          if (!projectName) {
            return '❌ Please specify project name';
          }
          // Normalize workspace and project names to kebab-case
          const normalizedWorkspace = normalizeWorkspaceName(workspace);
          const project = await this.workspaceManager.createProject(normalizedWorkspace, projectName);
          return `✅ Created project: ${project.name} in workspace ${normalizedWorkspace}`;
        }

        case 'list_projects': {
          const workspace = intent.workspace || intent.target;
          if (!workspace) {
            return '❌ Please specify workspace name';
          }
          // Normalize workspace name to kebab-case
          const normalizedWorkspace = normalizeWorkspaceName(workspace);
          const projects = await this.workspaceManager.listProjects(normalizedWorkspace);
          if (projects.length === 0) {
            return `No projects in workspace "${normalizedWorkspace}"`;
          }
          const projectList = projects.map((p, index) => `${index + 1}. ${p.name}`).join('. ');
          return `${projects.length} projects: ${projectList}`;
        }

        case 'create_terminal_in_project': {
          const workspace = intent.workspace;
          const projectName = intent.name || intent.project;
          const terminalType = intent.terminal_type || 'cursor';
          
          if (!workspace || !projectName) {
            return '❌ Please specify workspace and project name';
          }

          if (!_terminalManager) {
            return '❌ Terminal manager is not available';
          }

          // Normalize workspace and project names to kebab-case
          const normalizedWorkspace = normalizeWorkspaceName(workspace);
          const normalizedProjectName = normalizeRepositoryName(projectName);
          const normalizedTerminalName = `${normalizedWorkspace}-${normalizedProjectName}-${terminalType}`;

          try {
            const projectPath = await this.workspaceManager.getProjectPath(normalizedWorkspace, normalizedProjectName);
            const newSession = await _terminalManager.createSession(terminalType, projectPath, normalizedTerminalName);
            return `✅ Created ${terminalType} terminal in project: ${normalizedProjectName}`;
          } catch (error) {
            const errorMessage = error instanceof Error ? error.message : 'Unknown error';
            return `❌ Error: ${errorMessage}`;
          }
        }

        default:
          return `❌ Unknown workspace operation: ${action}`;
      }
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return `❌ Error in workspace operation: ${errorMessage}`;
    }
  }

  private async handleWorktreeOperation(intent: Intent, _sessionId: string, terminalManager?: TerminalManager): Promise<string> {
    if (!this.worktreeManager) {
      return '❌ Worktree manager is not available';
    }

    const action = intent.action;

    try {
      switch (action) {
        case 'create_worktree': {
          const workspace = intent.workspace;
          const repo = intent.repo;
          const branchOrFeature = intent.branch_or_feature || intent.target;
          
          if (!workspace) {
            return '❌ Please specify workspace name';
          }
          if (!repo) {
            return '❌ Please specify repository name';
          }
          if (!branchOrFeature) {
            return '❌ Please specify branch or feature name';
          }

          // Normalize all names to kebab-case
          const normalizedWorkspace = normalizeWorkspaceName(workspace);
          const normalizedRepo = normalizeRepositoryName(repo);
          const normalizedBranch = normalizeBranchName(branchOrFeature);
          const normalizedWorktreeName = intent.name ? normalizeTerminalName(intent.name) : undefined;

          const worktree = await this.worktreeManager.createWorktree(normalizedWorkspace, normalizedRepo, normalizedBranch, normalizedWorktreeName);
          return `✅ Created worktree: ${worktree.name} (branch: ${worktree.branch})`;
        }

        case 'remove_worktree': {
          const workspace = intent.workspace;
          const repo = intent.repo;
          const worktreeName = intent.name || intent.target;
          
          if (!workspace) {
            return '❌ Please specify workspace name';
          }
          if (!repo) {
            return '❌ Please specify repository name';
          }
          if (!worktreeName) {
            return '❌ Please specify worktree name to remove';
          }

          // Normalize all names to kebab-case
          const normalizedWorkspace = normalizeWorkspaceName(workspace);
          const normalizedRepo = normalizeRepositoryName(repo);
          const normalizedWorktreeName = normalizeTerminalName(worktreeName);

          await this.worktreeManager.removeWorktree(normalizedWorkspace, normalizedRepo, normalizedWorktreeName);
          return `✅ Removed worktree: ${normalizedWorktreeName}`;
        }

        case 'list_worktrees': {
          const workspace = intent.workspace;
          const repo = intent.repo;
          
          if (!workspace) {
            return '❌ Please specify workspace name';
          }
          if (!repo) {
            return '❌ Please specify repository name';
          }

          // Normalize workspace and repository names to kebab-case
          const normalizedWorkspace = normalizeWorkspaceName(workspace);
          const normalizedRepo = normalizeRepositoryName(repo);

          const worktrees = await this.worktreeManager.listWorktrees(normalizedWorkspace, normalizedRepo);
          if (worktrees.length === 0) {
            return `No worktrees for "${normalizedRepo}" in "${normalizedWorkspace}"`;
          }
          const worktreeList = worktrees.map((w, index) => `${index + 1}. ${w.name} (${w.branch})`).join('. ');
          return `${worktrees.length} worktrees: ${worktreeList}`;
        }

        case 'create_terminal_in_worktree': {
          const workspace = intent.workspace;
          const repo = intent.repo;
          const worktreeName = intent.name || intent.target;
          const terminalType = intent.terminal_type || 'cursor';
          
          if (!workspace || !repo || !worktreeName) {
            // Try to infer from context or ask for clarification
            return '❌ Please specify workspace, repository, and worktree name';
          }

          if (!terminalManager) {
            return '❌ Terminal manager is not available';
          }

          // Normalize all names to kebab-case
          const normalizedWorkspace = normalizeWorkspaceName(workspace);
          const normalizedRepo = normalizeRepositoryName(repo);
          const normalizedWorktreeName = normalizeTerminalName(worktreeName);
          const normalizedTerminalName = `${normalizedWorkspace}-${normalizedRepo}-${terminalType}`;

          // Validate worktree exists
          const isValid = await this.worktreeManager.validateWorktree(normalizedWorkspace, normalizedRepo, normalizedWorktreeName);
          if (!isValid) {
            return `❌ Worktree "${normalizedWorktreeName}" does not exist or is invalid`;
          }

          const worktreePath = this.worktreeManager.getWorktreePath(normalizedWorkspace, normalizedRepo, normalizedWorktreeName);
          const newSession = await terminalManager.createSession(terminalType, worktreePath, normalizedTerminalName);
          return `✅ Created ${terminalType} terminal in worktree: ${normalizedWorktreeName}`;
        }

        default:
          return `❌ Unknown worktree operation: ${action}`;
      }
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      return `❌ Error in worktree operation: ${errorMessage}`;
    }
  }
}
