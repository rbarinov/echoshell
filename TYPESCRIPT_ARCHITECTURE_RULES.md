# TypeScript Architecture & Development Best Practices

This document defines ideal architecture patterns and development approaches for TypeScript applications in this project (laptop-app and tunnel-server).

## Table of Contents

1. [Architecture Principles](#architecture-principles)
2. [Code Organization](#code-organization)
3. [Type Safety](#type-safety)
4. [Error Handling](#error-handling)
5. [Logging & Observability](#logging--observability)
6. [Testing](#testing)
7. [Performance](#performance)
8. [Security](#security)
9. [Code Quality](#code-quality)
10. [CI/CD & Build Process](#cicd--build-process)

---

## Architecture Principles

### 1. Separation of Concerns (SoC)
- **Single Responsibility Principle (SRP)**: Each module/class should have one reason to change
- **Dependency Inversion**: Depend on abstractions, not concrete implementations
- **Interface Segregation**: Create focused, minimal interfaces

**Examples:**
```typescript
// ✅ Good: Single responsibility
class TerminalManager {
  createSession(): TerminalSession { }
  deleteSession(id: string): void { }
}

class OutputRouter {
  routeOutput(type: OutputType, data: string): void { }
}

// ❌ Bad: Multiple responsibilities
class TerminalManager {
  createSession(): TerminalSession { }
  routeOutput(): void { }
  validateInput(): boolean { }
  sendEmail(): void { }
}
```

### 2. Modular Architecture
- **Feature-based organization**: Group related functionality together
- **Clear module boundaries**: Each module should have a clear purpose
- **Minimal coupling**: Modules should depend on as few other modules as possible

**Directory Structure:**
```
src/
├── handlers/          # Request handlers (HTTP/tunnel)
├── routes/            # Express route definitions
├── schemas/           # Zod validation schemas
├── utils/             # Shared utilities
├── output/            # Output processing logic
├── terminal/          # Terminal management
└── types.ts           # Shared type definitions
```

### 3. Dependency Injection
- **Constructor injection**: Pass dependencies through constructor
- **Avoid global state**: Use dependency injection instead of singletons
- **Testability**: Dependencies should be easily mockable

**Example:**
```typescript
// ✅ Good: Dependency injection
class TerminalHandler {
  constructor(
    private terminalManager: TerminalManager,
    private logger: Logger
  ) {}
}

// ❌ Bad: Global state
class TerminalHandler {
  private terminalManager = TerminalManager.getInstance();
}
```

---

## Code Organization

### 1. File Structure
- **One class/interface per file**: Keep files focused and maintainable
- **Barrel exports**: Use `index.ts` for clean imports
- **Consistent naming**: Use kebab-case for files, PascalCase for classes

**Example:**
```
src/handlers/
├── terminalHandler.ts
├── keyHandler.ts
└── index.ts          # Re-exports all handlers
```

### 2. Import Organization
- **Group imports**: External → Internal → Types
- **Absolute imports**: Use path aliases for cleaner imports
- **No circular dependencies**: Structure code to avoid cycles

**Example:**
```typescript
// ✅ Good: Organized imports
import { z } from 'zod';
import { Router } from 'express';

import { TerminalManager } from '../terminal/TerminalManager';
import { logger } from '../utils/logger';

import type { TerminalSession } from '../types';
```

### 3. Barrel Exports
- **Use index.ts**: Create barrel files for clean public APIs
- **Explicit exports**: Only export what's needed

**Example:**
```typescript
// src/handlers/index.ts
export { TerminalHandler } from './terminalHandler';
export { KeyHandler } from './keyHandler';
```

---

## Type Safety

### 1. Strict TypeScript Configuration
- **Enable strict mode**: `"strict": true` in tsconfig.json
- **No `any` types**: Use `unknown` and type guards instead
- **Explicit return types**: Always specify function return types

**Example:**
```typescript
// ✅ Good: Explicit types
function processData(input: unknown): ProcessedData {
  if (!isValidInput(input)) {
    throw new Error('Invalid input');
  }
  return transform(input);
}

// ❌ Bad: Implicit any
function processData(input) {
  return transform(input);
}
```

### 2. Runtime Validation with Zod
- **Validate all inputs**: Use Zod schemas for runtime validation
- **Type inference**: Leverage Zod's type inference
- **Consistent validation**: Use validation utilities

**Example:**
```typescript
// ✅ Good: Zod validation
import { z } from 'zod';

const CreateTerminalSchema = z.object({
  session_id: z.string().min(1),
  terminal_type: z.enum(['regular', 'cursor', 'claude']),
  working_dir: z.string().optional(),
});

type CreateTerminalRequest = z.infer<typeof CreateTerminalSchema>;

function createTerminal(data: unknown): TerminalSession {
  const validated = CreateTerminalSchema.parse(data);
  // validated is now type-safe
}
```

### 3. Type Guards
- **Narrow types**: Use type guards for runtime type checking
- **Reusable guards**: Create shared type guard functions

**Example:**
```typescript
function isHeadlessTerminal(
  type: TerminalType
): type is HeadlessTerminalType {
  return type === 'cursor' || type === 'claude';
}
```

---

## Error Handling

### 1. Explicit Error Handling
- **Never ignore errors**: Always handle or propagate errors
- **Custom error types**: Create domain-specific error classes
- **Error context**: Include relevant context in error messages

**Example:**
```typescript
// ✅ Good: Explicit error handling
class TerminalError extends Error {
  constructor(
    message: string,
    public readonly sessionId?: string,
    public readonly code?: string
  ) {
    super(message);
    this.name = 'TerminalError';
  }
}

try {
  await terminalManager.createSession(config);
} catch (error) {
  if (error instanceof TerminalError) {
    logger.error('Terminal creation failed', { sessionId: error.sessionId });
  }
  throw error;
}
```

### 2. Error Propagation
- **Fail fast**: Don't swallow errors silently
- **Structured errors**: Use error objects with context
- **Log before throw**: Log errors before re-throwing

**Example:**
```typescript
// ✅ Good: Proper error propagation
async function handleRequest(req: Request): Promise<Response> {
  try {
    const result = await processRequest(req);
    return successResponse(result);
  } catch (error) {
    logger.error('Request processing failed', { error, requestId: req.id });
    throw error; // Re-throw for middleware to handle
  }
}
```

### 3. Async Error Handling
- **Use async/await**: Prefer async/await over raw promises
- **Promise.allSettled**: Use when partial failures are acceptable
- **Timeout handling**: Always set timeouts for async operations

**Example:**
```typescript
// ✅ Good: Proper async error handling
async function executeWithTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number
): Promise<T> {
  const timeout = new Promise<never>((_, reject) => {
    setTimeout(() => reject(new Error('Timeout')), timeoutMs);
  });
  
  return Promise.race([promise, timeout]);
}
```

---

## Logging & Observability

### 1. Structured Logging
- **JSON format**: Use structured JSON logs for parsing
- **Log levels**: Use appropriate levels (DEBUG, INFO, WARN, ERROR)
- **Context objects**: Include relevant context in logs

**Example:**
```typescript
// ✅ Good: Structured logging
logger.info('Terminal session created', {
  sessionId: session.id,
  terminalType: session.terminalType,
  workingDir: session.workingDir,
});

logger.error('Failed to create session', {
  error: error.message,
  stack: error.stack,
  sessionId: requestedId,
});
```

### 2. Log Levels
- **DEBUG**: Detailed information for debugging
- **INFO**: General informational messages
- **WARN**: Warning messages for potentially harmful situations
- **ERROR**: Error events that might still allow the app to continue

**Guidelines:**
- Use DEBUG for development-only logs
- Use INFO for important business events
- Use WARN for recoverable issues
- Use ERROR for failures that need attention

### 3. Sensitive Data
- **Never log secrets**: API keys, passwords, tokens
- **Sanitize data**: Remove sensitive fields before logging
- **Mask PII**: Mask personally identifiable information

**Example:**
```typescript
// ✅ Good: Sanitized logging
logger.info('API key issued', {
  deviceId: request.deviceId,
  expiresAt: key.expiresAt,
  // Never log: key.openaiKey
});
```

---

## Testing

### 1. Test Organization
- **Co-located tests**: Keep tests near source files
- **Test naming**: Use descriptive test names
- **Test structure**: Arrange-Act-Assert pattern

**Example:**
```typescript
describe('TerminalManager', () => {
  describe('createSession', () => {
    it('should create a regular terminal session', () => {
      // Arrange
      const manager = new TerminalManager();
      const config = { terminalType: 'regular' as const };
      
      // Act
      const session = manager.createSession(config);
      
      // Assert
      expect(session.terminalType).toBe('regular');
      expect(session.sessionId).toBeDefined();
    });
  });
});
```

### 2. Test Coverage
- **Unit tests**: Test individual functions/classes in isolation
- **Integration tests**: Test component interactions
- **Edge cases**: Test error conditions and boundary cases

### 3. Mocking
- **Mock dependencies**: Use mocks for external dependencies
- **Mock utilities**: Create reusable mock helpers
- **Avoid over-mocking**: Don't mock what you're testing

**Example:**
```typescript
// ✅ Good: Focused mocking
const mockTerminalManager = {
  createSession: jest.fn(),
  deleteSession: jest.fn(),
} as unknown as TerminalManager;

const handler = new TerminalHandler(mockTerminalManager);
```

---

## Performance

### 1. Async Operations
- **Non-blocking**: Use async/await for I/O operations
- **Concurrent operations**: Use Promise.all for parallel operations
- **Streaming**: Use streams for large data processing

**Example:**
```typescript
// ✅ Good: Concurrent operations
const [sessions, workspaces] = await Promise.all([
  terminalManager.listSessions(),
  workspaceManager.listWorkspaces(),
]);
```

### 2. Resource Management
- **Cleanup**: Always clean up resources (file handles, connections)
- **Connection pooling**: Reuse connections when possible
- **Memory leaks**: Avoid closures that capture large objects

**Example:**
```typescript
// ✅ Good: Resource cleanup
class TerminalSession {
  private cleanup(): void {
    this.pty.destroy();
    this.outputListeners.clear();
  }
  
  destroy(): void {
    this.cleanup();
  }
}
```

### 3. Optimization
- **Lazy loading**: Load modules only when needed
- **Caching**: Cache expensive computations
- **Debouncing/Throttling**: Use for frequent events

---

## Security

### 1. Input Validation
- **Validate all inputs**: Use Zod schemas for validation
- **Sanitize data**: Clean user input before processing
- **Type checking**: Validate types at runtime

**Example:**
```typescript
// ✅ Good: Input validation
function handleRequest(req: Request): Response {
  const validated = RequestSchema.parse(req.body);
  // validated is safe to use
}
```

### 2. Secrets Management
- **Environment variables**: Store secrets in .env files
- **Never commit secrets**: Use .gitignore for .env files
- **Secure storage**: Use secure storage mechanisms

### 3. Command Injection Prevention
- **Validate commands**: Whitelist allowed commands
- **Sanitize inputs**: Escape special characters
- **Use parameterized commands**: Avoid string concatenation

**Example:**
```typescript
// ✅ Good: Safe command execution
const allowedCommands = ['ls', 'pwd', 'cd'];
if (!allowedCommands.includes(command)) {
  throw new Error('Command not allowed');
}
```

---

## Code Quality

### 1. Code Style
- **Consistent formatting**: Use Prettier or similar
- **ESLint rules**: Enforce code quality rules
- **Naming conventions**: Use clear, descriptive names

### 2. Documentation
- **JSDoc comments**: Document public APIs
- **README files**: Keep documentation up to date
- **Code comments**: Explain "why", not "what"

**Example:**
```typescript
/**
 * Creates a new terminal session with the specified configuration.
 * 
 * @param config - Terminal session configuration
 * @returns The created terminal session
 * @throws {TerminalError} If session creation fails
 */
createSession(config: TerminalConfig): TerminalSession {
  // Implementation
}
```

### 3. Refactoring
- **Small changes**: Make incremental improvements
- **Remove dead code**: Delete unused code regularly
- **Simplify**: Prefer simple solutions over complex ones

### 4. Code Review Checklist
- [ ] Type safety: No `any` types
- [ ] Error handling: All errors handled
- [ ] Logging: Appropriate log levels
- [ ] Tests: New code has tests
- [ ] Documentation: Public APIs documented
- [ ] Performance: No obvious performance issues
- [ ] Security: No security vulnerabilities

---

## Module-Specific Guidelines

### Handlers
- **Single responsibility**: One handler per resource type
- **Validation**: Validate all inputs using Zod
- **Error handling**: Return appropriate HTTP status codes
- **Logging**: Log important events

### Routes
- **Thin routes**: Routes should only delegate to handlers
- **Middleware**: Use middleware for cross-cutting concerns
- **Validation**: Validate request bodies/params

### Schemas
- **Zod schemas**: Use Zod for all validation
- **Type inference**: Export inferred types
- **Reusability**: Create reusable schema components

### Utils
- **Pure functions**: Prefer pure functions when possible
- **No side effects**: Utils should be stateless
- **Well-tested**: Utils should have comprehensive tests

---

## Anti-Patterns to Avoid

### ❌ God Objects
```typescript
// ❌ Bad: Too many responsibilities
class Manager {
  createTerminal() { }
  deleteTerminal() { }
  routeOutput() { }
  validateInput() { }
  sendEmail() { }
  processPayment() { }
}
```

### ❌ Deep Nesting
```typescript
// ❌ Bad: Deep nesting
if (condition1) {
  if (condition2) {
    if (condition3) {
      // Hard to read
    }
  }
}

// ✅ Good: Early returns
if (!condition1) return;
if (!condition2) return;
if (!condition3) return;
```

### ❌ Magic Numbers/Strings
```typescript
// ❌ Bad: Magic values
if (status === 200) { }
setTimeout(() => {}, 5000);

// ✅ Good: Named constants
const HTTP_OK = 200;
const SESSION_TIMEOUT_MS = 5000;
```

### ❌ Ignoring Errors
```typescript
// ❌ Bad: Silent failures
try {
  await riskyOperation();
} catch (error) {
  // Ignored
}

// ✅ Good: Proper error handling
try {
  await riskyOperation();
} catch (error) {
  logger.error('Operation failed', { error });
  throw error;
}
```

---

## CI/CD & Build Process

### 1. GitHub Actions Workflows (MANDATORY)

**CRITICAL**: All Node.js/TypeScript applications that are published as packages MUST have GitHub Actions workflows for automated publishing to GitHub Packages.

#### Required Workflow Structure

Every publishable package must have a workflow file in `.github/workflows/` with the following requirements:

1. **Trigger Events**:
   - Push to main branch (for specific package paths)
   - Release creation
   - Manual dispatch (workflow_dispatch)

2. **Required Steps** (in order):
   - Checkout repository
   - Setup Node.js with GitHub Packages registry
   - Install dependencies (`npm ci`)
   - **Run npm audit** (MANDATORY - must pass)
   - **Run tests** (MANDATORY - must pass)
   - Type check (`npm run type-check`)
   - Build package (`npm run build`)
   - Publish to GitHub Packages

3. **Security Audit**:
   - `npm audit` MUST run before build
   - Workflow MUST fail if vulnerabilities are found
   - Use `npm audit --audit-level=moderate` or stricter

4. **Testing**:
   - Tests MUST run before publishing
   - Workflow MUST fail if tests fail
   - Use `npm test` or equivalent test command

#### Example Workflow Template

```yaml
name: Publish Package to GitHub Packages

on:
  push:
    branches:
      - main
    paths:
      - 'package-name/**'
      - '.github/workflows/publish-package-name.yml'
  release:
    types: [created]
  workflow_dispatch:
    inputs:
      version:
        description: 'Version to publish (e.g., 1.0.1)'
        required: false
        type: string

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          registry-url: 'https://npm.pkg.github.com'
          scope: '@your-scope'
      
      - name: Configure npm for GitHub Packages
        run: |
          echo "@your-scope:registry=https://npm.pkg.github.com" >> ~/.npmrc
          echo "//npm.pkg.github.com/:_authToken=${{ secrets.GITHUB_TOKEN }}" >> ~/.npmrc
      
      - name: Install dependencies
        working-directory: ./package-name
        run: npm ci
      
      - name: Run security audit
        working-directory: ./package-name
        run: npm audit --audit-level=moderate
      
      - name: Run tests
        working-directory: ./package-name
        run: npm test
      
      - name: Type check
        working-directory: ./package-name
        run: npm run type-check
      
      - name: Build package
        working-directory: ./package-name
        run: npm run build
      
      - name: Update version if provided
        if: ${{ github.event.inputs.version != '' }}
        working-directory: ./package-name
        run: |
          npm version ${{ github.event.inputs.version }} --no-git-tag-version
      
      - name: Publish to GitHub Packages
        working-directory: ./package-name
        run: npm publish
        env:
          NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### 2. Build Process Requirements

#### Pre-Build Checks (MANDATORY)

Before building any package, the following MUST be executed and pass:

1. **Security Audit**:
   ```bash
   npm audit --audit-level=moderate
   ```
   - Must run in CI/CD pipeline
   - Must fail build if vulnerabilities found
   - Can be run locally with `npm audit`

2. **Tests**:
   ```bash
   npm test
   ```
   - All tests must pass
   - Test coverage should be maintained
   - Tests must run in CI/CD before publishing

3. **Type Checking**:
   ```bash
   npm run type-check
   ```
   - TypeScript compilation must succeed
   - No type errors allowed

#### Build Steps

1. **Install Dependencies**:
   - Use `npm ci` in CI/CD (faster, reproducible)
   - Use `npm install` for local development

2. **Build**:
   - Run `npm run build`
   - Ensure `dist/` directory is created
   - Verify all source files are compiled

3. **Publish**:
   - Only publish if all checks pass
   - Use `npm publish` with proper authentication
   - Version should be managed via `package.json`

### 3. Package Configuration

#### package.json Requirements

For packages published to GitHub Packages:

```json
{
  "name": "@your-scope/package-name",
  "version": "1.0.0",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com"
  },
  "scripts": {
    "test": "jest",
    "type-check": "tsc --noEmit",
    "build": "tsc",
    "prepublishOnly": "npm run build"
  }
}
```

#### Required Scripts

- `test`: Run test suite
- `type-check`: TypeScript type checking
- `build`: Build the package
- `prepublishOnly`: Automatically runs before publish (ensures build)

### 4. Workflow Best Practices

#### Error Handling

- **Fail fast**: Stop on first error
- **Clear error messages**: Use descriptive step names
- **Conditional steps**: Use `if` conditions appropriately

#### Performance

- **Cache dependencies**: Cache `node_modules` when possible
- **Parallel jobs**: Run tests and type-check in parallel if possible
- **Matrix builds**: Test on multiple Node.js versions if needed

#### Security

- **Never commit secrets**: Use GitHub Secrets
- **Use GITHUB_TOKEN**: For GitHub Packages authentication
- **Audit dependencies**: Always run npm audit
- **Lock files**: Commit `package-lock.json`

### 5. Local Development

#### Pre-Commit Checks

Before committing, developers should run:

```bash
# Security audit
npm audit

# Tests
npm test

# Type check
npm run type-check

# Build (to verify)
npm run build
```

#### Pre-Publish Checklist

Before publishing manually (if needed):

- [ ] All tests pass
- [ ] npm audit passes
- [ ] Type check passes
- [ ] Build succeeds
- [ ] Version updated in package.json
- [ ] CHANGELOG updated (if maintained)
- [ ] README updated (if needed)

### 6. Enforcement

**CRITICAL**: These requirements are mandatory for all publishable Node.js packages:

- ❌ **NO package should be published without a GitHub Actions workflow**
- ❌ **NO package should be published without running npm audit**
- ❌ **NO package should be published without running tests**
- ❌ **NO package should be published if audit or tests fail**

---

## Summary

Follow these principles for maintainable, scalable TypeScript applications:

1. **Separation of Concerns**: One responsibility per module
2. **Type Safety**: Strict types, runtime validation with Zod
3. **Error Handling**: Explicit, structured error handling
4. **Logging**: Structured logging with appropriate levels
5. **Testing**: Comprehensive test coverage
6. **Security**: Input validation, secure secrets management
7. **Code Quality**: Clean, documented, maintainable code
8. **CI/CD**: Automated builds with security audits and tests

These rules apply to both `laptop-app` and `tunnel-server` projects.

### CI/CD Requirements Summary

- ✅ **GitHub Actions workflow** required for all publishable packages
- ✅ **npm audit** must run and pass before publishing
- ✅ **Tests** must run and pass before publishing
- ✅ **Type check** must pass before publishing
- ✅ **Build** must succeed before publishing
