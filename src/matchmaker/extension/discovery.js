/**
 * Copyright (c) 2022 Oracle and/or its affiliates. All rights reserved.
 * The Universal Permissive License (UPL), Version 1.0
 */

const dns = require('dns').promises;

class ServiceDiscovery {

  /**
   * create a service discovery instance
   * @param {string} service service name for dns lookup
   */
  constructor(service) {
    this.service = service;
    if (!service) {
      throw new Error('service name is required for address discovery');
    }
  }

  /**
   * get addresses
   * @param {string | number} [port] optional port to filter results if multiple ports are advertised
   * @returns {dns.Address[]} 
   * @example in kubernetes these will have the following syntax:
   * 
   * ```json
   * [{
   *   name: <pod-ip-addr>.<servicename>.<namespace>.svc.cluster.local,
   *   port: 3000
   * }]
   * ```
   */
  getAddresses(port) {
    return dns.resolveSrv(this.service)
      .then(list => port ? list.filter(a => a.port === ~~port) : list);
  }

}

module.exports = ServiceDiscovery;
