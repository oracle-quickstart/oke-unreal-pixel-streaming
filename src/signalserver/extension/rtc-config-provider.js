/**
 * Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
 * The Universal Permissive License (UPL), Version 1.0
 */
const { HttpClient } = require('./http');

/**
 * Adapter to the turn api service
 * @author Matt Vander Vliet
 */
module.exports = class RTCConfigProvider {

  /**
   * construct a game client 
   * @param {*} options
   * @param {string} options.service https? rest url for the turn api service
   */
  constructor(options) {
    const { service } = options;
    this._service = service && new HttpClient(service);
  }

  /**
   * send an interaction to the game
   * @param {RTCPeerConnection} config 
   * @returns {Promise<*>} API response data
   */
  getConfiguration(config) {
    return new Promise((resolve, reject) => {
      if (config?.iceServers?.length) {
        console.warn('Configured with fixed RTCPeerConnection options');
        return resolve(config);
      } else if (this._service) {
        return this._service.get()
          .then(res => resolve(res && res.data))
          .catch(reject)
      } else {
        reject(new Error('turn configuration service is not specified'))
      }
    });
  }
}
