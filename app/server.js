'use strict';

const express = require('express');

const app = express();
const PORT = process.env.PORT || 8080;

// Basic request logging - not structured/JSON here since this is a toy app,
// but see docs/observability.md for how this would be structured in production.
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} ${req.method} ${req.path}`);
  next();
});

app.get('/', (req, res) => {
  res.status(200).json({
    message: 'Henkel technical assessment sample service',
    docs: '/health',
  });
});

// Required by the assessment brief: liveness/readiness endpoint used by the
// container HEALTHCHECK, Kubernetes/Container Apps probes, and CI smoke tests.
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

// Only start the HTTP server when this file is run directly, so the test
// suite can import the app without binding a port.
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`Server listening on port ${PORT}`);
  });
}

module.exports = app;
