# AI Agent Capabilities Guide

This document describes the capabilities of the AI agent running on the laptop server. The agent can understand natural language commands and execute various operations on your system.

## Overview

The AI agent is powered by GPT-4 and can handle a wide range of commands through natural language. You can interact with the agent via voice commands (through the mobile app) or text input.

## Command Categories

### 1. Terminal Commands

Simple shell commands that execute directly in the terminal.

**Examples:**
- "list files in this directory"
- "check npm version"
- "show disk usage"
- "run npm install"
- "display current directory"

### 2. File Operations

Create, read, and manage files and directories.

**Examples:**
- "create a new file called test.js"
- "read the package.json file"
- "delete the old.log file"
- "create a directory named projects"

### 3. Git Operations

Standard git commands for version control.

**Examples:**
- "show git status"
- "create a new branch called feature-auth"
- "commit changes with message 'fix bug'"
- "push to remote repository"
- "show git log"

### 4. System Information

Query system information and resources.

**Examples:**
- "show system information"
- "list running processes"
- "check disk usage"
- "show memory usage"

### 5. Terminal Management

Create, delete, list, and manage terminal sessions.

**Examples:**
- "create a new terminal"
- "create a Cursor Agent terminal"
- "create a Cursor Agent terminal in /Users/me/projects"
- "list all terminals"
- "delete terminal session-123"
- "rename terminal session-123 to dev"
- "go to /Users/me/projects"

### 6. Workspace Management

Organize your work into workspaces and manage repositories.

**Examples:**
- "create workspace my-workspace"
- "list workspaces"
- "remove workspace my-workspace"
- "clone https://github.com/user/repo into workspace my-workspace"
- "list repositories in workspace my-workspace"

### 7. Worktree Management

Create and manage git worktrees for parallel feature development.

**Examples:**
- "create worktree feature-auth for repo myrepo in workspace my-workspace"
- "list worktrees for repo myrepo in workspace my-workspace"
- "remove worktree feature-auth from repo myrepo in workspace my-workspace"
- "create cursor agent terminal in worktree feature-auth of repo myrepo in workspace my-workspace"

### 8. Complex Multi-Step Tasks

Tasks that require multiple commands executed in sequence.

**Examples:**
- "clone repo and install dependencies"
- "create a new React app"
- "build and test the project"
- "set up a new project with git and npm"

### 9. Questions and Help

Ask questions and get guidance.

**Examples:**
- "what is the current directory?"
- "how do I install npm?"
- "what commands are available?"
- "explain git worktrees"

## Workflow Examples

### Complete Workflow: Creating a Feature Branch with Worktree

1. **Create a workspace:**
   ```
   "create workspace my-project"
   ```

2. **Clone a repository:**
   ```
   "clone https://github.com/user/myrepo into workspace my-project"
   ```

3. **Create a worktree for a new feature:**
   ```
   "create worktree feature-auth for repo myrepo in workspace my-project"
   ```

4. **Create a terminal in the worktree:**
   ```
   "create cursor agent terminal in worktree feature-auth of repo myrepo in workspace my-project"
   ```

5. **Work in the worktree:**
   - The terminal is now in the worktree directory
   - You can run commands, make changes, and commit them
   - Each worktree has its own branch and working directory

### Switching Between Worktrees

1. **List available worktrees:**
   ```
   "list worktrees for repo myrepo in workspace my-project"
   ```

2. **Create a new terminal in a different worktree:**
   ```
   "create cursor agent terminal in worktree feature-payment of repo myrepo in workspace my-project"
   ```

## Best Practices

### Workspace Organization

- Use descriptive workspace names (e.g., "client-projects", "personal", "open-source")
- Group related repositories in the same workspace
- Keep workspace names simple: use letters, numbers, hyphens, and underscores only

### Worktree Naming

- Worktrees are automatically named using the pattern: `{repo_name}-{feature_name}`
- Use clear, descriptive feature names (e.g., "feature-auth", "bugfix-login", "refactor-api")
- Avoid special characters in feature names

### When to Use Worktrees

- **Use worktrees when:**
  - You need to work on multiple features simultaneously
  - You want to test different branches without switching
  - You need to compare code between branches
  - You're working on a long-running feature and need to switch contexts

- **Use regular branches when:**
  - You're working on a single feature at a time
  - You don't need parallel development environments
  - You prefer switching branches in the same directory

### Terminal Session Management

- Name your terminals for easy identification
- Use Cursor Agent terminals for AI-assisted development
- Regular terminals are better for simple command execution
- Delete unused terminals to keep the list clean

## Error Handling

### Common Errors and Solutions

**"Workspace does not exist"**
- Make sure you've created the workspace first
- Check the workspace name spelling

**"Repository already exists"**
- The repository is already cloned in the workspace
- Use a different repository or remove the existing one

**"Worktree already exists"**
- A worktree with that name already exists
- Remove the existing worktree or use a different name

**"Working directory does not exist"**
- The specified path doesn't exist
- Check the path spelling and ensure the directory exists

**"Git command failed"**
- Check that git is installed and configured
- Verify repository access permissions
- Ensure you're not in a detached HEAD state

## Tips and Tricks

1. **Use natural language:** The agent understands various phrasings, so you don't need to use exact commands.

2. **Be specific:** When working with workspaces and repositories, include all necessary information:
   - Workspace name
   - Repository name
   - Worktree/feature name

3. **Combine operations:** You can describe multi-step workflows in a single command:
   ```
   "create workspace my-project and clone https://github.com/user/repo into it"
   ```

4. **Ask for help:** If you're unsure about available commands, just ask:
   ```
   "what can you do?"
   "how do I create a worktree?"
   ```

## Command Reference

### Workspace Commands
- `create workspace <name>` - Create a new workspace
- `list workspaces` - List all workspaces
- `remove workspace <name>` - Remove a workspace
- `clone <url> into workspace <name>` - Clone repository into workspace
- `list repositories in workspace <name>` - List repositories in workspace

### Worktree Commands
- `create worktree <feature> for repo <repo> in workspace <workspace>` - Create worktree
- `list worktrees for repo <repo> in workspace <workspace>` - List worktrees
- `remove worktree <name> from repo <repo> in workspace <workspace>` - Remove worktree
- `create terminal in worktree <name>` - Create terminal in worktree

### Terminal Commands
- `create terminal` - Create regular terminal
- `create cursor agent terminal` - Create Cursor Agent terminal
- `list terminals` - List all terminals
- `delete terminal <session-id>` - Delete terminal
- `rename terminal <session-id> to <name>` - Rename terminal

## Getting Started

1. **Create your first workspace:**
   ```
   "create workspace my-projects"
   ```

2. **Clone a repository:**
   ```
   "clone https://github.com/user/repo into workspace my-projects"
   ```

3. **Create a worktree for a feature:**
   ```
   "create worktree feature-new-ui for repo repo in workspace my-projects"
   ```

4. **Start working:**
   ```
   "create cursor agent terminal in worktree feature-new-ui of repo repo in workspace my-projects"
   ```

Now you're ready to work with the AI agent! Experiment with different commands and find the workflow that works best for you.

