/**
 * Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
 * The Universal Permissive License (UPL), Version 1.0
 */
const WebSocket = require('ws');
const http = require('http');
const prometheus = require('prom-client');

module.exports = class MetricsAdapter {

  constructor(options) {
    this.options = options;
    this.prefix = options?.prefix || '';
    const { register, Registry, collectDefaultMetrics } = prometheus;
    
    this.register = register;
    this.customReg = new Registry();
    collectDefaultMetrics({
      prefix: this.prefix,
      register,
    });
  };

  /**
   * create a new gauge metric
   * @param {string} name name of metric
   * @param {object} [options] gauge options
   * @returns {this}
   * @see https://www.npmjs.com/package/prom-client
   */
  gauge(name, options) {
    const g = new prometheus.Gauge({
      name: this.prefix + name,
      help: name,
      registers: [this.register, this.customReg],
      ...(options || {}),
    });
    return this;
  }

  /**
   * add instrumentation to the websocket server
   * @param {Websocket.Server} server 
   * @param {string} name the metric name
   */
  instrumentSocketServer(server, name) {
    return this.gauge(`${name}_socket_connections`, {
      help: `${name} websocket connections gauge`,
      collect() {
        this.set(server.clients.size);
      },
    });
  }

  /**
   * instrument a websocket or net.socket connection
   * @param {WebSocket.Socket | Net.Socket} socket 
   * @param {*} name 
   */
  instrumentSocket(socket, name) {
    return this.gauge(`${name}_socket_open_indicator`, {
      help: `${name} socket connection gauge`,
      collect() {
        this.set(['open', WebSocket.OPEN].includes(socket?.readyState) ? 1 : 0);
      }
    });
  }

  /**
   * create server and listen on the given port
   * @returns 
   */
  listen(cb) {
    const { port = 9000 } = this.options || {};
    this.server = http.createServer((req, res) => {
      if (req.url === '/custom') {
        this.respondFromRegistry(this.customReg, res);
      } else {
        this.respondFromRegistry(this.register, res);
      }
    });
    this.server.listen(port, cb);
    return this;
  }

  /**
   * respond from a specific registry
   * @param {Registry} registry 
   * @param {HttpResponse} res 
   * @returns 
   */
  respondFromRegistry(registry, res) {
    return registry.metrics()
      .then(text => {
        res.writeHead(200, { 'Content-Type': this.register.contentType });
        res.end(text);
      }).catch(e => {
        res.writeHead(500).end(e)
      });
  }

};
