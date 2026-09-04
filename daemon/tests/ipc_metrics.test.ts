import test from 'node:test';
import assert from 'node:assert/strict';
import { IPCChannel } from '../src/ipc.js';
import http from 'node:http';

test('ipc: serves Prometheus /metrics and /health over HTTP', async () => {
  const testPort = 19876;
  const channel = new IPCChannel(testPort, () => {}, {
    token: '',
    metricsHandler: () => {
      return '# HELP test_metric A test gauge\n# TYPE test_metric gauge\ntest_metric 42\n';
    },
  });

  try {
    // Test /health
    const healthData = await new Promise<string>((resolve, reject) => {
      http.get(`http://127.0.0.1:${testPort}/health`, (res) => {
        let data = '';
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => resolve(data));
      }).on('error', reject);
    });
    const parsedHealth = JSON.parse(healthData);
    assert.equal(parsedHealth.status, 'ok');

    // Test /metrics
    const metricsData = await new Promise<string>((resolve, reject) => {
      http.get(`http://127.0.0.1:${testPort}/metrics`, (res) => {
        let data = '';
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => resolve(data));
      }).on('error', reject);
    });
    assert.ok(metricsData.includes('test_metric 42'));
    assert.ok(metricsData.includes('# TYPE test_metric gauge'));
  } finally {
    channel.close();
  }
});
