import http from 'node:http';

const port = Number(process.env.PORT ?? 9800);
const mode = process.env.MODE ?? 'ok';

const server = http.createServer((req, res) => {
  if (mode === 'malformed') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end('{not valid json');
    return;
  }
  if (mode === 'hanging') {
    return;
  }
  if (mode === 'error500') {
    res.writeHead(500, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: 'boom' }));
    return;
  }
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(
      JSON.stringify({
        id: 1,
        model: 'fixture',
        choices: [{ message: { role: 'assistant', content: 'fixture completion' } }],
        usage: { total_tokens: 12 },
      })
    );
  });
});

server.listen(port, '127.0.0.1', () => {
  console.log(JSON.stringify({ domain: 'mock-upstream', level: 'info', code: 'upstream_ready', msg: `port ${port} mode ${mode}` }));
});
setInterval(() => {}, 1 << 30);
