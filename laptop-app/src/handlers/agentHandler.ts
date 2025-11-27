import type { AIAgent } from '../agent/AIAgent';
import type { TerminalManager } from '../terminal/TerminalManager';
import type { TunnelRequest, TunnelResponse } from '../types';
import { ExecuteAgentRequestSchema } from '../schemas/agentSchemas';
import { validateRequest } from '../utils/validation';
import logger from '../utils/logger';

export class AgentHandler {
  constructor(
    private aiAgent: AIAgent,
    private terminalManager: TerminalManager
  ) {}

  async handleRequest(req: TunnelRequest): Promise<TunnelResponse> {
    const { method, path, body } = req;

    if (path === '/agent/execute' && method === 'POST') {
      return this.handleExecute(body);
    }

    return { statusCode: 404, body: { error: 'Not found' } };
  }

  private async handleExecute(body: unknown): Promise<TunnelResponse> {
    const validation = validateRequest(ExecuteAgentRequestSchema, body);
    if (!validation.success) {
      return validation.response;
    }

    const { command, session_id } = validation.data;

    logger.info('AI Agent executing', { command, sessionId: session_id || null });

    // session_id is optional - agent can work without terminal context for workspace/worktree operations
    const result = await this.aiAgent.execute(command, session_id, this.terminalManager);

    return {
      statusCode: 200,
      body: {
        type: 'ai_response',
        session_id: result.sessionId || session_id || null,
        command,
        result: result.output,
        via: 'ai_agent'
      }
    };
  }
}
