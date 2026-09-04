import { WebSocketServer, WebSocket } from 'ws';
import { createServer as createHttpServer } from 'node:http';
import { createServer as createHttpsServer } from 'node:https';
import type { Server as HttpServer } from 'node:http';
import type { Server as HttpsServer } from 'node:https';
import { readFileSync, existsSync } from 'node:fs';
import { WS_MAX_FRAME_BYTES, WS_TOKEN, IS_PRODUCTION, WS_TLS_CERT, WS_TLS_KEY } from './config.js';
import { structLog } from './errors.js';

export interface ServerMessage {
  type: string;
  [k: string]: unknown;
}

export interface ClientCommand {
  type: string;
  repoId?: string;
  name?: string;
  masterPlan?: string;
  sessionId?: string;
}

type CommandHandler = (command: ClientCommand, reply: (message: ServerMessage) => void) => void;

export interface IPCChannelOptions {
  token?: string;
  snapshot?: () => ServerMessage[];
  maxClients?: number;
  metricsHandler?: () => string;
}

export class IPCChannel {
  private wss: WebSocketServer;
  private server: HttpServer | HttpsServer;
  private clients = new Set<WebSocket>();
  private authenticated = new WeakSet<WebSocket>();
  private readonly token: string;
  private readonly snapshot: () => ServerMessage[];
  private readonly maxClients: number;

  constructor(port: number, handler: CommandHandler, options: IPCChannelOptions = {}) {
    this.token = options.token ?? WS_TOKEN;
    if (IS_PRODUCTION && (!this.token || this.token.trim().length === 0)) {
      throw new Error('SECURITY HALT: ORCH_WS_TOKEN is mandatory when running in production mode (NODE_ENV=production)');
    }
    this.snapshot = options.snapshot ?? (() => []);
    this.maxClients = options.maxClients ?? 16;

    const requestListener = (req: import('node:http').IncomingMessage, res: import('node:http').ServerResponse) => {
      const url = new URL(req.url ?? '/', `http://${req.headers.host ?? '127.0.0.1'}`);
      if (url.pathname === '/metrics' && req.method === 'GET') {
        const metrics = options.metricsHandler ? options.metricsHandler() : '# No metrics registered\n';
        res.writeHead(200, { 'Content-Type': 'text/plain; version=0.0.4' });
        res.end(metrics);
        return;
      }
      if (url.pathname === '/health' && req.method === 'GET') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'ok', clients: this.clients.size }));
        return;
      }
      if (req.headers.upgrade?.toLowerCase() !== 'websocket') {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not Found\n');
      }
    };

    if (WS_TLS_CERT && WS_TLS_KEY && existsSync(WS_TLS_CERT) && existsSync(WS_TLS_KEY)) {
      this.server = createHttpsServer({
        cert: readFileSync(WS_TLS_CERT),
        key: readFileSync(WS_TLS_KEY),
      }, requestListener);
    } else {
      this.server = createHttpServer(requestListener);
    }
    this.server.listen(port, '127.0.0.1');
    this.wss = new WebSocketServer({ server: this.server });

    this.wss.on('connection', (socket) => {
      if (this.clients.size >= this.maxClients) {
        socket.close(1013, 'server saturated');
        return;
      }
      this.clients.add(socket);
      const reply = (message: ServerMessage) => {
        if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(message));
      };
      if (this.token.length === 0) {
        for (const message of this.snapshot()) {
          reply(message);
        }
      }
      const isAuthed = () => this.token.length === 0 || this.authenticated.has(socket);
      socket.on('message', (raw) => {
        const size = Array.isArray(raw)
          ? raw.reduce((n, b) => n + b.length, 0)
          : raw instanceof ArrayBuffer
            ? raw.byteLength
            : raw.length;
        if (size > WS_MAX_FRAME_BYTES) {
          structLog({ level: 'warning', code: 'frame_overflow', msg: `frame ${size} bytes rejected` });
          socket.close(1013, 'frame overflow');
          return;
        }
        let command: ClientCommand;
        try {
          command = JSON.parse(String(raw));
        } catch {
          structLog({ level: 'warning', code: 'bad_client_frame', msg: 'invalid json command' });
          reply({ type: 'error', code: 'bad_client_frame', detail: 'invalid json command' });
          return;
        }
        if (!isAuthed()) {
          if (command.type === 'auth' && (command as { token?: string }).token === this.token) {
            this.authenticated.add(socket);
            for (const message of this.snapshot()) {
              reply(message);
            }
            return;
          }
          structLog({ level: 'warning', code: 'auth_rejected', msg: 'ws client rejected — token required' });
          socket.close(1008, 'auth required');
          return;
        }
        handler(command, reply);
      });
      socket.on('close', () => this.clients.delete(socket));
      socket.on('error', () => this.clients.delete(socket));
    });
  }

  broadcast(message: ServerMessage): void {
    const payload = JSON.stringify(message);
    for (const client of this.clients) {
      if (client.readyState === WebSocket.OPEN) client.send(payload);
    }
  }

  get clientCount(): number {
    return this.clients.size;
  }

  close(): void {
    for (const client of this.clients) {
      if (client.readyState === WebSocket.OPEN) client.close();
    }
    this.clients.clear();
    this.wss.close();
    this.server.close();
  }
}
