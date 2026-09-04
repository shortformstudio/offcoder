import { WebSocket } from 'ws';

export function wsClient(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    const messages = [];
    let closeCodeResolve;
    const closeCodePromise = new Promise((r) => (closeCodeResolve = r));
    ws.on('message', (raw) => {
      try {
        messages.push(JSON.parse(String(raw)));
      } catch {
        /* ignore malformed frames */
      }
    });
    ws.on('open', () => {
      resolve({
        send: (obj) => ws.send(JSON.stringify(obj)),
        sendRaw: (data) => ws.send(data),
        messages,
        waitForType: (type, timeoutMs = 15_000, predicate) =>
          new Promise((res, rej) => {
            const start = Date.now();
            const tick = () => {
              const hit = messages.find((m) => m.type === type && (!predicate || predicate(m)));
              if (hit) return res(hit);
              if (Date.now() - start > timeoutMs) return rej(new Error(`no ${type} within ${timeoutMs}ms`));
              setTimeout(tick, 80);
            };
            tick();
          }),
        closeCode: () => closeCodePromise,
        close: () => ws.close(),
      });
    });
    ws.on('close', (code) => closeCodeResolve(code));
    ws.on('error', (err) => reject(err));
  });
}
