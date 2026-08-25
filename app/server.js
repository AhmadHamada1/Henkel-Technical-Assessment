'use strict';

const express = require('express');

const app = express();
const PORT = process.env.PORT || 8080;

// Plain logging here; see docs/observability.md for the structured version.
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

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

// Only bind a port when run directly, so tests can import the app instead.
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`Server listening on port ${PORT}`);
  });
}

module.exports = app;
