import { WebSocket, WebSocketServer } from 'ws';
import type { TerminalManager } from '../terminal/TerminalManager';
import type { OutputRouter } from '../output/OutputRouter';

/**
 * Setup WebSocket server for terminal streaming (localhost only)
 */
export function setupTerminalWebSocket(
  wss: WebSocketServer,
  terminalManager: TerminalManager,
  outputRouter: OutputRouter
): void {
  wss.on('connection', (ws, req) => {
    // Check if connection is from localhost
    const clientIp = req.socket.remoteAddress || '';
    const isLocalhost =
      clientIp === '127.0.0.1' ||
      clientIp === '::1' ||
      clientIp === '::ffff:127.0.0.1';

    if (!isLocalhost) {
      console.warn(`⚠️  WebSocket connection rejected from non-localhost: ${clientIp}`);
      ws.close(1008, 'Access denied. WebSocket is only available on localhost.');
      return;
    }

    // Extract session ID from path
    const url = new URL(req.url || '', 'http://localhost');
    const sessionIdMatch = url.pathname.match(/\/terminal\/([^\/]+)\/stream/);

    if (!sessionIdMatch) {
      ws.close(1008, 'Invalid session ID');
      return;
    }

    const sessionId = sessionIdMatch[1];
    console.log(`📡 WebSocket connected for session: ${sessionId}`);

    // Add output listener for this WebSocket via OutputRouter
    const outputListener = (data: string) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(
          JSON.stringify({
            type: 'output',
            session_id: sessionId,
            data: data,
            timestamp: Date.now()
          })
        );
      }
    };

    // Register WebSocket listener with OutputRouter
    outputRouter.addWebSocketListener(sessionId, outputListener);

    // Handle input from web interface
    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString()) as { type: string; data?: string };

        if (message.type === 'input' && message.data) {
          terminalManager.writeInput(sessionId, message.data);
        }
      } catch (error) {
        console.error('❌ Error processing WebSocket message:', error);
      }
    });

    ws.on('close', () => {
      console.log(`📡 WebSocket disconnected for session: ${sessionId}`);
      outputRouter.removeWebSocketListener(sessionId, outputListener);
    });

    ws.on('error', (error) => {
      console.error(`❌ WebSocket error for session ${sessionId}:`, error);
    });
  });
}
