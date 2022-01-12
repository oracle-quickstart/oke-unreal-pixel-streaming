/**
 * Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
 * The Universal Permissive License (UPL), Version 1.0
 */
const WebSocket = require('ws');

// bring in custom utils
const MetricsAdapter = require('./extension/metrics');
const UnrealAPIClient = require('./extension/unreal-client');
const RTCConfigProvider = require('./extension/rtc-config-provider');

/**
 * This wrapper class orchestrates the signaler runtime with some customizations
 * and extensions
 */
class CirrusWrapper {

  /**
   * instantiate wrapper
   * @param {cirrus} main 
   */
  constructor(main) {
    // capture main app
    this.app = main;
    // deconstruct relevant configs
    const { config: { ueRestEndpoint, rtcConfigSvc, metricsPort } } = main;
    // instantiate the custom game client adapter, rtc provider, and metrics
    this.api = new UnrealAPIClient({ endpoint: ueRestEndpoint });
    this.rtc = new RTCConfigProvider({ service: rtcConfigSvc });
    this.metrics = new MetricsAdapter({ port: metricsPort, prefix: 'signalserver_' });
    // add a series of shutdown handlers
    this.shutdownHandlers = new Set();
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
  shutdown(event) {

    const doShutdown = async () => {
      this._info('processing shutdown handlers for signal', event);
      await Promise.all([...this.shutdownHandlers.values()]
        .map(cb => Promise.resolve(cb())))
        .catch(e => this._error('graceful shutdown error:', e));
      this._info('shutdown complete. exiting');
      process.exit(0);
    };
    // check player connections and allow open sessions to remain open until
    // player disconnects
    const { playerServer } = this.app;
    if (playerServer.clients.size) {
      this._info('defer shutdown until player(s) disconnect or terminationGracePeriodSeconds is exceeded');
      playerServer.clients.forEach(ws => {
        ws.send(JSON.stringify({ type: 'sigterm', message: 'stream will shutdown' }));
        ws.once('close', () => doShutdown());
      });
    } else {
      doShutdown();
    }
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
    return this;
  }

  /**
   * perform any extra/custom instrumentation
   * @returns {this}
   */
  setupInstrumentation() {
    const {
      playerServer,   // player websocket server
      streamerServer, // streamer (pixel stream) websocket server
      streamer,       // connected streamer socket
      matchmaker,     // matchmaker net.socket
    } = this.app;

    this.metrics
      .instrumentSocketServer(playerServer, 'player')
      .instrumentSocketServer(streamerServer, 'stream')
      .instrumentSocket(streamer, 'stream')
      .instrumentSocket(matchmaker, 'matchmaker')
      .gauge('free_stream_indicator', {
        collect() {
          this.set(
            !playerServer.clients.size &&
            streamer?.readyState === WebSocket.OPEN ? 1 : 0
          );
        }
      });
    
    // add shutdown handler
    this.registerShutdown(() => {
      this._info('close metrics server');
      return new Promise(resolve => this.metrics.server ? this.metrics.server.close(resolve) : resolve());
    });

    return this;
  }

  /**
   * perform any necessary extensions on the main app objects
   */
  setupExtensions() {
    this.extendHttpServer();
    this.extendSocketServers();
    this.extendPlayerSockets();
    this.extendMatchmakerSocket();
    return this;
  }

  /**
   * add http server extensions
   */
  extendHttpServer() {
    const { app, streamerServer } = this.app;

    // add healthcheck for readiness
    app.get('/healthz', (req, res) => {
      const ok = streamerServer.clients.size > 0;
      res.status(ok ? 200 : 503).send(ok ? 'ok' : 'unhealthy');
    });
  }

  /**
   * apply extensions to the websocket servers
   */
  extendSocketServers() {
    const { streamerServer, playerServer } = this.app;
  
    [streamerServer, playerServer].forEach(wss => {
      // listen to socket connections
      wss.on('connection', this.handleSocketConnection.bind(this));
      // register a shutdown handler on the wss
      this.registerSocketShutdown(wss);
    });

  }

  /**
   * extensions for individual player connections
   */
  extendPlayerSockets() {
    const { playerServer } = this.app;

    // additional special handlers for player server
    playerServer.on('connection', ws => {
      this._info('customize player connection');
      // add ping/pong/alive
      ws.alive = true;
      ws.on('pong', () => ws.alive = true);

      // add custom message handler for websocket=>rest adapter
      // this is added because of data size limitations on the WebRTC data
      // channel. 
      ws.on('message', msg => {
        try {
          msg = JSON.parse(msg);
          // handle custom message type(s)
          if (msg.type === 'control') {
            const { action, payload } = msg;
            this.api.request(action, payload)
              .then(response => ws.send(JSON.stringify({ type: 'response', action, response })))
              .catch(error => ws.send(JSON.stringify({ type: 'response', action, error })));
          }
        } catch (e) {
          this._error(e);
        }
      });
    });

    // add heartbeat ping/pong to keep TCP connection alive
    // otherwise load balancers are likely to close the connection
    // after a finite TTL
    const playerPing = setInterval(() => {
      playerServer.clients.forEach(ws => {
        if (!ws.alive) {
          return ws.terminate();
        } else {
          ws.alive = false;
          ws.ping();
        }
      })
    }, 3e4); // every 30s
    
    this.registerShutdown(() => clearInterval(playerPing));
  }

  /**
   * add matchmaker extensions/hooks
   */
  extendMatchmakerSocket() {
    const { matchmaker } = this.app;
    const ueRestPort = ~~this.api.port();
    
    if (matchmaker) {
      // catch the socket write to intercept 'connect' message details
      const mme = matchmaker.emit.bind(matchmaker);
      // redefine the emit to catch each 'connect' event
      matchmaker.emit = (event, ...args) => {
        if (event === 'connect') {
          // on connect, extend the new writeable stream
          const mmw = matchmaker.write.bind(matchmaker);
          matchmaker.write = (msg) => {
            try {
              const m = JSON.parse(msg);
              if (m.type === 'connect') {
                // add additional extensions details for matchmaker
                // to provide affinity to the streamer
                Object.assign(m, {
                  restPort: ueRestPort, // port for rest API
                });
                this._info('extended mm connection information');
              }
              mmw(JSON.stringify(m));
            } catch (e) {
              mmw(msg);
            }
          }
        }
        mme(event, ...args);
      };
      
    } else {
      this._info('## running without matchmaker ##');
    }
  }

  /**
   * route client configuration through the rtc connection option provider
   * @author Matt Vander Vliet
   * @param {Socket} socket streamer or websocket
   * @param {IncomingRequest} [request] the incoming connection request
   */
  handleSocketConnection(socket, request) {
    const { clientConfig } = this.app;
    this._info('supply rtc configuation to socket');
    this.rtc.getConfiguration(clientConfig.peerConnectionOptions)
      .then(peerConnectionOptions =>
        socket.send(JSON.stringify({
          ...clientConfig,
          peerConnectionOptions,
        }))
      ).catch(e => this._error('turn discovery peer configuration error', e));
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
module.exports = new CirrusWrapper(require('./cirrus')).run();
