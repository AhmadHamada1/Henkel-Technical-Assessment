'use strict';

// Uses Node's built-in test runner to avoid an extra dependency.
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');

const app = require('../server');

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, () => resolve(server));
  });
}

function get(server, path) {
  const { port } = server.address();
  return new Promise((resolve, reject) => {
    http
      .get(`http://127.0.0.1:${port}${path}`, (res) => {
        let body = '';
        res.on('data', (chunk) => (body += chunk));
        res.on('end', () => {
          resolve({ statusCode: res.statusCode, body: JSON.parse(body) });
        });
      })
      .on('error', reject);
  });
}

test('GET /health returns 200 and status ok', async (t) => {
  const server = await startServer();
  t.after(() => server.close());

  const res = await get(server, '/health');

  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, { status: 'ok' });
});

test('GET / returns 200', async (t) => {
  const server = await startServer();
  t.after(() => server.close());

  const res = await get(server, '/');

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.message, 'Henkel technical assessment sample service');
});
