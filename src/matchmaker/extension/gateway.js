/**
 * Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
 * The Universal Permissive License (UPL), Version 1.0
 */
const Net = require('net');
const Http = require('http');
const WebSocket = require('ws');
const { v4: uuid } = require('uuid');
const { EventEmitter } = require('events');
const MetricsAdapter = require('./metrics');
const ServiceDisovery = require('./discovery');

const isOpen = (ws) => 
  ws && ws.readyState === WebSocket.OPEN;

const parseQuery = str => 
  new URLSearchParams(str.split('?').pop());

/**
 * A simple base class for this utility
 */
class Common extends EventEmitter {
  constructor(...args) {
    super(...args);
    this._id = Common._id++;
  }

  _log(...args) {
    console.log(`${this.constructor.name} [${this._id}]:`, ...args);
  }
}
Common._id = 0;

/**
 * Main extension entrypoint takes the matchmaker http server
 * and net server (socket) from signaler as its arguments
 */
class PlayerConnectionGateway extends Common {

  /**
   * create a player connection websocket system on the http server
   * @param {object} options
   * @param {http.Server} options.server an exitsting http server (could replace with standalone init/server)
   * @param {Net.Server} options.matchmaker the matchmaker TCP server
   * @param {Map<*>} options.pool cirrus server pool
   * @param {MetricsAdapter} options.metrics metrics adapter
   * @param {number} options.lastPingMax maximum time since last ping before removal
   */
  constructor(options) {
    super();
    const { server, matchmaker, pool, streamSvc, metrics, lastPingMax, debug } = options || {};
    if (!(server instanceof Http.Server)) {
      throw new Error('Http server is required for PlayerConnectionGateway');
    }
    if (!(matchmaker instanceof Net.Server)) {
      throw new Error('Matchmaker server is required for PlayerConnectionGateway');
    }
    if (!pool instanceof Map) {
      throw new Error('A streamer availability pool is required');
    }
    if (!metrics instanceof MetricsAdapter) {
      throw new Error('Metrics adapter instance is required');
    }

    // FUTURE: instantiate stream service discovery discovery
    // this.discovery = new ServiceDisovery(streamSvc);

    // get the maximum time elapsed since last ping
    this.pingMax = lastPingMax || null;

    // for debug/development
    this._debug = !!debug;

    // setup lookup/pool finding
    this.pool = pool;

    // queue of waiting clients
    const queue = this.queue = new Set();

    // setup websocket server on the shared http server 
    const wss = this.wss = new WebSocket.Server({ server });
    wss.on('connection', this.onClientConnection.bind(this));

    // listen to upstream matchmaker TCP connections
    matchmaker.on('connection', this.onStreamerConnection.bind(this));

    // add instruments
    metrics
      .instrumentSocketServer(wss, 'player')
      .gauge('player_queue_count', {
        collect() { this.set(queue.size); }
      })
      .gauge('streamer_available_count', {
        collect() {
          this.set([...pool.values()]
            .filter(s => s.numConnectedClients === 0 && s.ready === true)
            .length)
        }
      })
      .gauge('streamer_demand_ratio', {
        collect() {
          const players = wss.clients.size;
          const poolSize = [...pool.values()].filter(s => s.ready === true).length;
          this.set(poolSize > 0 ? players/poolSize :
            (players > 0 ? players + 1 : 0)) // case when there's no streamer pool
        }
      });

    // ready
    this._log(`initialized`);
  }

  /**
   * process waiting player queue and attempt matching to streamers
   * @returns {Promise<void>}
   */
  async connectWaitingPlayers() {
    const size = this.queue.size;
    if (size) {
      this._log(`dequeue ${size} waiting player(s)`);
      for (const player of this.queue.values()) {
        const server = await this.nextAvailable(player);
        if (server) {
          this.assignPlayer(player, server);
        } else {
          this._log('unmatched stream for player', player.id);
        }
      }
    }
  }

  /**
   * obtain a server with available connection
   * @param {VirtualPlayer} player queued/waiting connection
   * @returns {Promise<object>} matched server
   */
  async nextAvailable(player) {
    const liveTime = this.pingMax ? Date.now() - this.pingMax : 0;
    for (const server of this.pool.values()) {
      if (!server.offered && // being offered
        server.lastPingReceived >= liveTime &&    // still beating
        (server.ready === true || this._debug) && // readiness
        player.checkStreamCandidate(server)) { // player specific checks
        return server;
      }
    }
  }

  /**
   * assigns a player to a server for the lifecycle of the session
   * @param {VirtualPlayer} player 
   * @param {*} server 
   */
  assignPlayer(player, server) {
    this.queue.delete(player);
    if (isOpen(player.ws)) {
      // flag server as being offered
      server.offered = true;
      // handle dealloc
      const finishOffer = () => server.offered = null;
      player
        // if the streamer dropped, add player back to queue
        .once('drop', () => isOpen(player.ws) && this.queue.add(player))
        // when the player connects, free the server
        .once('connect', finishOffer)
        // make connection (returns the new socket to signal server)
        .connectStreamer(server)
          // likely a problem with the streamer... might not be reusable
          .on('error', finishOffer);
    }
  }

  /**
   * handle connection from a streamer application
   * @param {net.Socket} connection 
   * @see https://nodejs.org/api/net.html#class-netsocket
   */
  onStreamerConnection(socket) {
    // const addr = { port: 12346, family: 'IPv4', address: '127.0.0.1' }
    this._log('streamer registered', {
      local: `${socket.localAddress}:${socket.localPort}`,
      remote: `${socket.remoteAddress}:${socket.remotePort}`,
      family: socket.remoteFamily,
    });
    // handle socket emits  
    socket
      .on('error', (e) => this._log(`streamer socket error:`, e))
      // data from streamer usually changes availability or readiness
      .on('data', () => this.connectWaitingPlayers());
  }

  /**
   * handle an actual player websocket connection which acts as a virtual
   * gateway to the cirrus websocket listener
   * @param {*} ws 
   */
  onClientConnection(ws, req) {
    this._log('client connected', req.url);
    // add the player to a list of waiting players
    const player = new VirtualPlayer(ws, req.url);
    // auto dequeue on disconnect
    this.queue.add(player
      .on('disconnect', () => this.queue.delete(player)));
    // process waitlist (queue)
    this.connectWaitingPlayers();
  }

}


/**
 * Definition for a virtual player who holds the client
 * websocket connection and is assigned a server upon 
 * availability
 */
class VirtualPlayer extends Common {

  /**
   * instantiate with the waiting client websocket
   * @param {WebSocket} ws 
   */
  constructor(ws, url) {
    super();
    this.id = uuid();
    this.search = parseQuery(url);
    this._log('created virtual player instance:', this.id);
    // create heartbeat
    const hb = setInterval(this._clientHeartbeat.bind(this), 3e4);
    // setup on the client ws connection
    ws.alive = true;
    this.ws = ws;
    this.ws
      .on('pong', () => this.ws.alive = true) // pong from the server
      .on('message', this.onClientMessage.bind(this)) // relay to streamer
      .on('close', () => { clearInterval(hb); this.disconnect(); }); // maint
    // indicate wait
    this.sendNotice('Waiting for available streamer');
  }

  /**
   * interval ping/pong with client connection
   * @returns 
   */
  _clientHeartbeat() {
    const ws = this.ws;
    if (!ws.alive) {
      return ws.terminate();
    } else {
      ws.alive = false;
      ws.ping();
    }
  }

  /**
   * Evaluate candidacy of a player for the given stream
   * @param {*} stream
   * @returns {boolean}
   */
  checkStreamCandidate(stream) {
    const { id, address, numConnectedClients } = stream;
    const spec = this.search.get('id') || this.search.get('address');
    if (spec) {
      // evaluate against matching id or ip address
      return [id, address].includes(spec) || // exact match
        spec === '*'; // TODO: wildcard should be an optional config
    } else {
      // assume player just wants an empty session
      return numConnectedClients === 0;
    }
  }

  /**
   * pass client websocket messages to the stream (cirrus)
   * @param {*} msg 
   */
  onClientMessage(msg) {
    msg = msg.toString();
    this._log('--> forward client message to streamer -->');
    if (isOpen(this.stream)) {
      this.stream.send(msg);
    } else {
      this._log('cannot forward client message to non-existent stream');
    }
  }

  /**
   * pass cirrus websocket messages to the client
   * @param {*} msg 
   */
  onStreamerMessage(msg) {
    msg = msg.toString();
    this._log('<-- relay streamer message to client <--', msg);
    if (isOpen(this.ws)) {
      this.ws.send(msg);
    } else {
      this._log('cannot relay streamer message to non-existent client');
    }
  }

  /**
   * attach as a client to the designated signaler 
   * @param {*} backend
   * @returns {WebSocket} socket connection 
   */
  connectStreamer(backend) {
    this._log('connecting to stream', backend);

    function pong() {
      clearTimeout(this.pingTimeout);
      this.pingTimeout = setTimeout(() => {
        this.terminate();
      }, 30000 + 1000);
    }

    // setup base connection and listeners
    const { port, address } = backend;
    const ss = this.stream = new WebSocket(`ws://${address}:${port}?player=${this.id}`);
    ss.on('open', pong)
      .on('ping', pong)
      .on('close', function clear() { clearTimeout(this.pingTimeout) })

    // hook up functional listeners
    ss.on('open', () => this._log('connected to signal server'))
      .on('open', () => this.emit('connect'))
      .on('close', (e) => this.handleStreamerClose(e))
      .on('message', this.onStreamerMessage.bind(this));

    // notify the client that magic awaits
    this.sendNotice(backend);

    return ss;
  }

  /**
   * send a notice to the waiting client
   * @param {*} detail 
   */
  sendNotice(detail) {
    this.ws.send(JSON.stringify({
      type: 'matchmaker',
      queued: !this.stream,
      matched: !!this.stream,
      detail,
    }));
  }

  /**
   * handle case where streamer drops, but client is still possibly connected
   */
  handleStreamerClose(e) {
    this._log('player <--> streamer connection closed', e);
    this.stream = null;
    this.emit('drop', e);
    this.sendNotice('Streamer dropped');
  }

  /**
   * closes the virtual player connections
   */
  disconnect() {
    this._log('player allocation disconnect');
    this.emit('disconnect');
    this.ws.close();
    this.stream && this.stream.close();
  }

}

module.exports = PlayerConnectionGateway;
