/**
 * Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
 * The Universal Permissive License (UPL), Version 1.0
 */
const URL = require('url');
const { HttpClient } = require('./http');

/**
 * Adapter to the game system APIs
 * @author Matt Vander Vliet
 */
module.exports = class UnrealAPIClient {

  /**
   * construct an api client for unreal engine runtimes exposing REST
   * @param {object} options api client options
   * @param {string} options.endpoint https? rest url for the unreal application
   */
  constructor(options) {
    const { endpoint } = options;
    this._endpoint = endpoint;
    this._http = endpoint && new HttpClient(endpoint);
  }

  /**
   * getter for the rest port.
   * this assumes the port can be accessed on the same host (pod)
   * as the signaler
   */
  port() {
    const endpoint = this._endpoint || '';
    const url = URL.parse(endpoint);
    return url.port;
  }

  /**
   * send a request to the game API
   * @param {*} type API call (url)
   * @param {*} [data] data to POST, GET if no data is provided
   * @returns {Promise<*>} API response data
   */
  request(type, data) {
    return Promise.resolve(this._http ?
      (data ? this._http.post(type, data) : this._http.get(type)) :
      null) // noop when no http client exists (no endpoint)
      .then(res => res && res.data); // extract data property
  }
}