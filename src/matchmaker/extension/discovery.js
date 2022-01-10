/**
 * Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
 * The Universal Permissive License (UPL), Version 1.0
 */

const dns = require('dns');
const { promisify } = require('util');

class StreamDiscovery {
  constructor(streamService) {
    if (!streamService) {
      throw new Error('streamService name is required for address discovery');
    }
    this.serviceName = streamService;
  }

  getAddresses() {
    return promisify(dns.resolveSrv).call(dns, this.serviceName);
  }
}

module.exports = StreamDiscovery;
