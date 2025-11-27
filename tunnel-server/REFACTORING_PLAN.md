# Tunnel Server Refactoring Plan

This document outlines a comprehensive refactoring plan for the tunnel-server to align with TypeScript architecture best practices and Node.js development standards.

## Executive Summary

**Current State**: Single 706-line file with mixed responsibilities, no type safety, no tests, console.log-based logging.

**Target State**: Modular architecture with separation of concerns, full type safety, comprehensive tests, structured logging, and proper error handling.

**Timeline**: 4 weeks

**Key Improvements**:
- ✅ Modular structure (15+ focused modules)
- ✅ Type safety (Zod validation, no `any` types)
- ✅ Structured logging (JSON format)
- ✅ Comprehensive error handling
- ✅ Test coverage (>80%)
- ✅ Clear separation of concerns

## Current State Analysis

### Issues Identified

1. **Monolithic Structure**: All code in single `index.ts` file (706 lines)
2. **No Separation of Concerns**: HTTP, WebSocket, heartbeat, proxy logic all mixed together
3. **No Type Safety**: Extensive use of `any` types, no runtime validation
4. **No Structured Logging**: Using `console.log`/`console.error` instead of structured logging
5. **No Error Handling**: Errors are caught but not properly handled or logged
6. **No Input Validation**: No Zod schemas for request validation
7. **No Tests**: Zero test coverage
8. **No Module Organization**: Everything in one file
9. **Hard-coded Configuration**: Configuration logic mixed with business logic
10. **No Type Definitions**: WebSocket messages use `any` types

## Refactoring Goals

1. **Modular Architecture**: Split into focused modules with single responsibilities
2. **Type Safety**: Remove all `any` types, add Zod validation
3. **Structured Logging**: Implement JSON-based structured logging
4. **Error Handling**: Proper error handling with custom error types
5. **Testing**: Comprehensive test coverage
6. **Code Organization**: Clear module boundaries and barrel exports
7. **Configuration Management**: Centralized configuration handling
8. **Documentation**: JSDoc comments for all public APIs

## Refactoring Phases

### Phase 1: Foundation & Structure (Week 1) ✅

#### Task 1.1: Create Project Structure ✅
- [x] Create directory structure:
  ```
  src/
  ├── index.ts              # Main entry point (minimal)
  ├── server.ts             # Express & HTTP server setup
  ├── config/
  │   └── Config.ts         # Configuration management
  ├── types/
  │   └── index.ts          # Type definitions
  ├── schemas/
  │   └── tunnelSchemas.ts  # Zod validation schemas
  ├── utils/
  │   └── logger.ts         # Structured logging
  ├── tunnel/
  │   ├── TunnelManager.ts  # Tunnel connection management
  │   └── TunnelConnection.ts # Tunnel connection model
  ├── websocket/
  │   ├── WebSocketServer.ts # WebSocket server setup
  │   ├── handlers/
  │   │   ├── tunnelHandler.ts    # Tunnel WebSocket handler
  │   │   ├── streamHandler.ts    # Terminal stream handler
  │   │   └── recordingHandler.ts  # Recording stream handler
  │   └── heartbeat/
  │       └── HeartbeatManager.ts # Heartbeat management
  ├── proxy/
  │   └── HttpProxy.ts      # HTTP request proxying
  ├── routes/
  │   ├── tunnel.ts         # Tunnel creation routes
  │   └── health.ts         # Health check routes
  └── errors/
      └── TunnelError.ts    # Custom error types
  ```

#### Task 1.2: Create Type Definitions ✅
- [x] Define `TunnelConnection` interface
- [x] Define `StreamConnection` interface
- [x] Define WebSocket message types (no `any`)
- [x] Define request/response types
- [x] Export all types from `types/index.ts`

#### Task 1.3: Create Configuration Module ✅
- [x] Extract configuration logic to `config/Config.ts`
- [x] Load environment variables with validation
- [x] Provide typed configuration object
- [x] Handle .env file loading (service + root)
- [x] Validate required environment variables

#### Task 1.4: Create Structured Logger ✅
- [x] Create `utils/logger.ts` with JSON logging
- [x] Support log levels: DEBUG, INFO, WARN, ERROR
- [x] Include context objects in logs
- [x] Never log secrets (API keys, tokens)

### Phase 2: Core Modules (Week 1-2) ✅

#### Task 2.1: Create Tunnel Manager ✅
- [x] Create `tunnel/TunnelManager.ts`
- [x] Move tunnel connection storage logic
- [x] Implement tunnel registration
- [x] Implement tunnel lookup
- [x] Implement tunnel cleanup
- [x] Add proper error handling

#### Task 2.2: Create WebSocket Server Module ✅
- [x] Create `websocket/WebSocketServer.ts`
- [x] Extract WebSocket server setup
- [x] Implement connection routing
- [x] Delegate to specific handlers

#### Task 2.3: Create WebSocket Handlers ✅
- [x] Create `websocket/handlers/tunnelHandler.ts`
  - Handle tunnel WebSocket connections
  - Process tunnel messages
  - Manage tunnel lifecycle
- [x] Create `websocket/handlers/streamHandler.ts`
  - Handle terminal stream connections
  - Forward terminal input/output
- [x] Create `websocket/handlers/streamManager.ts`
  - Handle recording stream connections
  - Forward recording output (WebSocket + SSE)

#### Task 2.4: Create Heartbeat Manager ✅
- [x] Create `websocket/heartbeat/HeartbeatManager.ts`
- [x] Extract heartbeat logic from main file
- [x] Support tunnel and stream heartbeats
- [x] Implement dead connection detection
- [x] Clean up intervals on disconnect

### Phase 3: HTTP & Proxy (Week 2) ✅

#### Task 3.1: Create HTTP Proxy Module ✅
- [x] Create `proxy/HttpProxy.ts`
- [x] Extract HTTP proxying logic
- [x] Implement request forwarding to laptop
- [x] Implement response handling
- [x] Add timeout handling
- [x] Add proper error handling

#### Task 3.2: Create Routes ✅
- [x] Create `routes/tunnel.ts`
  - POST `/tunnel/create` with validation
- [x] Create `routes/health.ts`
  - GET `/health` endpoint
- [x] Create `routes/recording.ts`
  - GET `/api/:tunnelId/recording/:sessionId/events` (SSE)

#### Task 3.3: Create Server Setup Module ✅
- [x] Create `server.ts`
- [x] Extract Express app setup
- [x] Extract HTTP server setup
- [x] Extract middleware setup
- [x] Return configured server

### Phase 4: Type Safety & Validation (Week 2-3) ✅

#### Task 4.1: Create Zod Schemas ✅
- [x] Create `schemas/tunnelSchemas.ts`
  - `TunnelCreateRequestSchema`
  - `WebSocketMessageSchema`
  - `TerminalInputSchema`
  - `RecordingOutputSchema`
- [x] Export inferred types

#### Task 4.2: Add Validation ✅
- [x] Validate tunnel creation requests
- [x] Validate WebSocket messages
- [x] Validate HTTP proxy requests
- [x] Return proper error responses

#### Task 4.3: Remove All `any` Types ✅
- [x] Replace `any` with proper types
- [x] Use type guards where needed
- [x] Use Zod for runtime validation

### Phase 5: Error Handling (Week 3) ✅

#### Task 5.1: Create Custom Error Types ✅
- [x] Create `errors/TunnelError.ts`
  - `TunnelNotFoundError`
  - `TunnelAuthError`
  - `TunnelConnectionError`
  - `InvalidRequestError`
- [x] Include context in errors
- [x] Proper error messages

#### Task 5.2: Implement Error Handling ✅
- [x] Add try-catch blocks where needed
- [x] Log errors with context
- [x] Return appropriate HTTP status codes
- [x] Handle WebSocket errors gracefully

### Phase 6: Testing (Week 3-4)

#### Task 6.1: Setup Testing Infrastructure
- [ ] Add Jest configuration
- [ ] Add test utilities
- [ ] Add mock helpers
- [ ] Configure test scripts

#### Task 6.2: Unit Tests
- [ ] Test `TunnelManager`
- [ ] Test `HttpProxy`
- [ ] Test `HeartbeatManager`
- [ ] Test configuration loading
- [ ] Test validation schemas

#### Task 6.3: Integration Tests
- [ ] Test tunnel creation flow
- [ ] Test WebSocket connections
- [ ] Test HTTP proxying
- [ ] Test heartbeat mechanism
- [ ] Test stream connections

### Phase 7: Code Quality (Week 4) ✅

#### Task 7.1: Update Main Entry Point ✅
- [x] Simplify `index.ts` to minimal initialization (132 lines vs 705)
- [x] Import and use modules
- [x] Handle startup errors
- [x] Graceful shutdown

#### Task 7.2: Add Documentation ✅
- [x] JSDoc comments for all public APIs
- [ ] Update README.md (pending)
- [ ] Add code examples (pending)
- [ ] Document architecture (pending)

#### Task 7.3: Code Review & Cleanup ✅
- [x] Remove debug console.log statements (replaced with Logger)
- [x] Remove commented code
- [x] Ensure consistent code style
- [x] Run linter/type-check (✅ passes)

## Detailed Implementation Guide

### Module: `config/Config.ts`

```typescript
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

export interface TunnelServerConfig {
  port: number;
  host: string;
  publicHost: string;
  publicProtocol: 'http' | 'https';
  registrationApiKey: string;
  nodeEnv: 'development' | 'production';
  pingIntervalMs: number;
  pongTimeoutMs: number;
}

export class Config {
  private static config: TunnelServerConfig | null = null;

  static load(): TunnelServerConfig {
    if (this.config) {
      return this.config;
    }

    // Load .env files (service-specific, then root)
    this.loadEnvFiles();

    const registrationApiKey = process.env.TUNNEL_REGISTRATION_API_KEY;
    if (!registrationApiKey) {
      throw new Error('TUNNEL_REGISTRATION_API_KEY is required');
    }

    this.config = {
      port: parseInt(process.env.PORT || '8000', 10),
      host: process.env.HOST || '0.0.0.0',
      publicHost: process.env.PUBLIC_HOST || process.env.HOST || 'localhost',
      publicProtocol: (process.env.PUBLIC_PROTOCOL || 'http') as 'http' | 'https',
      registrationApiKey,
      nodeEnv: (process.env.NODE_ENV || 'development') as 'development' | 'production',
      pingIntervalMs: 20000,
      pongTimeoutMs: 30000,
    };

    return this.config;
  }

  private static loadEnvFiles(): void {
    // Implementation for loading .env files
  }
}
```

### Module: `utils/logger.ts`

```typescript
type LogLevel = 'DEBUG' | 'INFO' | 'WARN' | 'ERROR';

interface LogContext {
  [key: string]: unknown;
}

export class Logger {
  private static level: LogLevel = process.env.LOG_LEVEL as LogLevel || 'INFO';

  static debug(message: string, context?: LogContext): void {
    if (this.shouldLog('DEBUG')) {
      this.log('DEBUG', message, context);
    }
  }

  static info(message: string, context?: LogContext): void {
    this.log('INFO', message, context);
  }

  static warn(message: string, context?: LogContext): void {
    this.log('WARN', message, context);
  }

  static error(message: string, context?: LogContext): void {
    this.log('ERROR', message, context);
  }

  private static log(level: LogLevel, message: string, context?: LogContext): void {
    const logEntry = {
      timestamp: new Date().toISOString(),
      level,
      message,
      ...(context && { context: this.sanitize(context) }),
    };
    console.log(JSON.stringify(logEntry));
  }

  private static sanitize(context: LogContext): LogContext {
    // Remove secrets from context
    const sanitized = { ...context };
    const secretKeys = ['apiKey', 'api_key', 'token', 'password', 'authKey'];
    secretKeys.forEach(key => {
      if (sanitized[key]) {
        sanitized[key] = '***';
      }
    });
    return sanitized;
  }

  private static shouldLog(level: LogLevel): boolean {
    const levels: LogLevel[] = ['DEBUG', 'INFO', 'WARN', 'ERROR'];
    return levels.indexOf(level) >= levels.indexOf(this.level);
  }
}
```

### Module: `tunnel/TunnelManager.ts`

```typescript
import { WebSocket } from 'ws';
import { TunnelConnection } from './TunnelConnection';
import { Logger } from '../utils/logger';

export class TunnelManager {
  private tunnels = new Map<string, TunnelConnection>();

  register(tunnelId: string, apiKey: string, ws: WebSocket): TunnelConnection {
    const connection: TunnelConnection = {
      tunnelId,
      apiKey,
      ws,
      createdAt: Date.now(),
      lastPongReceived: Date.now(),
    };

    this.tunnels.set(tunnelId, connection);
    Logger.info('Tunnel registered', { tunnelId });
    return connection;
  }

  get(tunnelId: string): TunnelConnection | undefined {
    return this.tunnels.get(tunnelId);
  }

  delete(tunnelId: string): void {
    const tunnel = this.tunnels.get(tunnelId);
    if (tunnel) {
      this.tunnels.delete(tunnelId);
      Logger.info('Tunnel deleted', { tunnelId });
    }
  }

  getAll(): TunnelConnection[] {
    return Array.from(this.tunnels.values());
  }

  size(): number {
    return this.tunnels.size;
  }
}
```

### Module: `schemas/tunnelSchemas.ts`

```typescript
import { z } from 'zod';

export const TunnelCreateRequestSchema = z.object({
  name: z.string().optional(),
  tunnel_id: z.string().optional(),
});

export type TunnelCreateRequest = z.infer<typeof TunnelCreateRequestSchema>;

export const WebSocketMessageSchema = z.object({
  type: z.string(),
  requestId: z.string().optional(),
  statusCode: z.number().optional(),
  body: z.unknown().optional(),
});

export type WebSocketMessage = z.infer<typeof WebSocketMessageSchema>;

export const TerminalInputSchema = z.object({
  type: z.literal('input'),
  data: z.string(),
});

export type TerminalInput = z.infer<typeof TerminalInputSchema>;

export const RecordingOutputSchema = z.object({
  type: z.literal('recording_output'),
  sessionId: z.string(),
  text: z.string().optional(),
  delta: z.string().optional(),
  raw: z.unknown().optional(),
  timestamp: z.number().optional(),
  isComplete: z.boolean().optional(),
});

export type RecordingOutput = z.infer<typeof RecordingOutputSchema>;
```

### Module: `errors/TunnelError.ts`

```typescript
export class TunnelError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly statusCode: number = 500
  ) {
    super(message);
    this.name = 'TunnelError';
  }
}

export class TunnelNotFoundError extends TunnelError {
  constructor(tunnelId: string) {
    super(`Tunnel not found: ${tunnelId}`, 'TUNNEL_NOT_FOUND', 404);
  }
}

export class TunnelAuthError extends TunnelError {
  constructor(message: string = 'Unauthorized') {
    super(message, 'TUNNEL_AUTH_ERROR', 401);
  }
}

export class TunnelConnectionError extends TunnelError {
  constructor(message: string) {
    super(message, 'TUNNEL_CONNECTION_ERROR', 503);
  }
}

export class InvalidRequestError extends TunnelError {
  constructor(message: string) {
    super(message, 'INVALID_REQUEST', 400);
  }
}
```

## Migration Strategy

### Step-by-Step Migration

1. **Create new structure** alongside existing code
2. **Migrate one module at a time** (start with config, logger)
3. **Update imports** gradually
4. **Test each module** before moving to next
5. **Remove old code** once new code is working
6. **Update tests** as modules are migrated

### Backward Compatibility

- Maintain same API endpoints
- Maintain same WebSocket protocol
- Maintain same environment variables
- No breaking changes for clients

## Success Criteria

- [ ] All code split into focused modules
- [ ] Zero `any` types
- [ ] All inputs validated with Zod
- [ ] Structured logging throughout
- [ ] Comprehensive error handling
- [ ] Test coverage > 80%
- [ ] All tests passing
- [ ] TypeScript strict mode passes
- [ ] npm audit passes
- [ ] Documentation complete

## Timeline

- **Week 1**: Phases 1-2 (Foundation, Core Modules)
- **Week 2**: Phases 3-4 (HTTP/Proxy, Type Safety)
- **Week 3**: Phases 5-6 (Error Handling, Testing)
- **Week 4**: Phase 7 (Code Quality, Documentation)

## Notes

- Keep tunnel-server simple (it's a thin proxy)
- Focus on maintainability and testability
- Don't over-engineer
- Follow TYPESCRIPT_ARCHITECTURE_RULES.md principles
- Ensure backward compatibility
