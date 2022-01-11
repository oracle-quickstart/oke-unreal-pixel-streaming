/**
 * Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
 * The Universal Permissive License (UPL), Version 1.0
 */
const WebSocket = require('ws');
const { v4: uuid } = require('uuid');
const { promisify } = require('util');

// bring in custom utils
const MetricsAdapter = require('./extension/metrics');
const PlayerConnectionGateway = require('./extension/gateway');

// threshold for identifying dead connections
const LAST_PING_MAX = 6e4;

/**
 * This wrapper class orchestrates the matchmaker runtime with some customizations
 * and extensions
 */
class MatchmakerWrapper {

  /**
   * instantiate wrapper
   * @param {matchmaker} main 
   */
  constructor(main) {
    // capture main app
    this.app = main;
    // add a series of shutdown handlers
    this.shutdownHandlers = new Set();
    // deconstruct relevant configs
    const { http, matchmaker, cirrusServers, config: { metricsPort } } = main;
    // deconstruct env
    const { DEBUG, NAMESPACE, STREAM_SERVICE_NAME } = process.env;
    const streamSvc = STREAM_SERVICE_NAME + (NAMESPACE ? `.${NAMESPACE}.svc.cluster.local` : '');
    // instantiate the custom gateway, and metrics
    this.metrics = new MetricsAdapter({ port: metricsPort, prefix: 'matchmaker_' });
    this.gateway = new PlayerConnectionGateway({
      lastPingMax: LAST_PING_MAX, // threshold for identifying dead connections
      server: http,           // reuse the http server
      matchmaker,             // attach to matchmaker net.server
      pool: cirrusServers,    // forward the pool connection map
      metrics: this.metrics,  // provide metrics hooks
      streamSvc,              // dns name for internal (headless) stream service
      debug: !!DEBUG,         // debug
    });
    this.registerSocketShutdown(this.gateway.wss);

    // initialize wrapper features
    this.init();
  }

  _info(...args) {
    console.log(`${this.constructor.name} INFO:`, ...args);
  }
  _error(...args) {
    console.error(`${this.constructor.name} ERROR:`, ...args);
  }

  init() {
    this
      .setupInstrumentation()
      .setupExtensions()
      .setupGracefulShutdown();
  }

  /**
   * start any necessary services
   * @returns {this}
   */
  run() {
    // start metrics service
    this.metrics.listen(() => this._info('metrics service up'));
    return this;
  }

  /**
   * process shutdown
   * @param {*} event 
   */
  async shutdown(event) {
    this._info('processing shutdown handlers for signal', event);
    await Promise.all([...this.shutdownHandlers.values()]
      .map(cb => Promise.resolve(cb())))
      .catch(e => this._error('graceful shutdown error:', e));
    this._info('shutdown complete. exiting');
    process.exit(0);
  }

  /**
   * register a shutdown handler
   * @param {(): Promise<void>|void} cb 
   * @returns {this}
   */
  registerShutdown(cb) {
    this.shutdownHandlers.add(cb);
    return this;
  }

  /**
   * catch the process termination signals
   * @returns {this}
   */
  setupGracefulShutdown() {
    process.once('SIGTERM', this.shutdown.bind(this));

    const { http, matchmaker, cirrusServers } = this.app;
    
    // add shutdown handlers
    this.registerShutdown(() => {
      this._info('close metrics server');
      return new Promise(resolve => this.metrics.server ? this.metrics.server.close(resolve) : resolve())
        .then(() => this._info('metrics server closed'));
    })
    .registerShutdown(promisify(http.close).bind(http))
    .registerShutdown(promisify(matchmaker.close).bind(matchmaker))
    .registerShutdown(() =>
      cirrusServers.forEach((_, conn) => conn.destroy()));

    return this;
  }
  
  /**
   * perform any extra/custom instrumentation
   * @returns {this}
   */
  setupInstrumentation() {
    const {
      http,
      matchmaker,     // matchmaker net.server
    } = this.app;

    this.metrics.gauge('streamer_connections', {
      async collect() {
        this.set(await promisify(matchmaker.getConnections).call(matchmaker));
      }
    });

    return this;
  }

  /**
   * perform any necessary extensions on the main app objects
   */
  setupExtensions() {
    const {
      app,            // matchmaker express app
      matchmaker,     // matchmaker net.server
      cirrusServers,  // cirrus pool map
    } = this.app;

    // add basic healthcheck
    app.get('/healthz', (req, res) => res.send('ok'));

    // add basic list api
    app.get('/list', (req, res) => res.json([...cirrusServers.values()]));

    // setup pool monitor to detect lost pings (cirrus pings every 30s)
    setInterval(() => [...cirrusServers.values()]
      .filter(c => (c.lastPingReceived < (Date.now() - LAST_PING_MAX)))
      .forEach(c => cirrusServers.delete(c))
    , LAST_PING_MAX / 2);

    // handle cirrus connections (after main matchmaker.js)
    matchmaker.on('connection', connection => {
      // must capture the remote address of this connection.
      // It is the connection path back to cirrus 
      const address = connection.remoteAddress.split(':').pop();
      connection.on('data', msg => {
        try {
          msg = JSON.parse(msg);
          if (msg.type === 'connect') {
            const c = cirrusServers.get(connection); // lookup
            if (c) {
              this._info('extend streamer configuration');
              Object.assign(c, {
                id: uuid(), // create an identifier
                address,    // overload address as the internal connection (pod ip)
                restPort: msg.restPort || null, // the stream api port
              });
            } else {
              this._error('could not locate cirrus on connection');
            }
          }
        } catch (e) {
          this._error('unrecognized cirrus data', msg);
        }
      });
    });
    
    return this;
  }

  /**
   * gracefully handle socket shutdowns
   * @param {WebSocket.Server} wss 
   */
  registerSocketShutdown(wss) {
    this.registerShutdown(async () => {
      this._info('websocket server shutdown');
      // fire close
      wss.clients.forEach(ws => ws.close());
      wss.close();
      // wait and kill if necessary
      await new Promise(resolve => {
        setTimeout(() => resolve(wss.clients.forEach((socket) => {
          if ([WebSocket.OPEN, WebSocket.CLOSING].includes(socket.readyState)) {
            socket.terminate();
          }
        })), 2e3);
      });

      this._info('websocket server shutdown complete');
    });
  }
}

// run the wrapper with the main application
module.exports = new MatchmakerWrapper(require('./matchmaker')).run();
