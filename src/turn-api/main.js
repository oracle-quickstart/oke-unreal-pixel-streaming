/**
 * Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
 * The Universal Permissive License (UPL), Version 1.0
 */
const http = require('http');
const { getEnv } = require('./lib/env');
const { getRTCPeerConfig } = require('./lib/rtc');

const log = (...args) => console.log(`[${new Date().toUTCString()}] - INFO:`, ...args);
const err = (...args) => console.error(`[${new Date().toUTCString()}] - INFO:`, ...args);

// create a single handler to obtain peerCredentials for this node
const server = http.createServer(async (req, res) => {
  log(req.method, req.url);

  try {
    // main route
    if (req.url === '/') {
      const peerConfig = await getRTCPeerConfig();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(peerConfig));
    // healthcheck
    } else if (/^\/health/.test(req.url)) {
      const rtc = await getRTCPeerConfig();
      const ok = rtc.iceServers.some(s => s.urls.length);
      res.writeHead(ok ? 200 : 404).end(`${ok}`);
    // unknown
    } else {
      res.writeHead(404).end();
    }

  } catch (e) {
    res.writeHead(500).end('Error');
    err(e);
  }
    
  
});

// start on the configured port
server.listen(getEnv('PORT', 3000), () => {
  log('service started');
});

// handle termination
process.once('SIGTERM', () =>
  server.close(() => process.exit(0)));

module.exports = server;
