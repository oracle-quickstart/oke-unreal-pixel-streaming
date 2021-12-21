/**
 * Copyright (c) 2021, Oracle and/or its affiliates. All rights reserved.
 * The Universal Permissive License (UPL), Version 1.0
 */
const fs = require('fs');
const { getEnv } = require("./env")
const { getTURNCredentials } = require("./cred");

const endpointFile = getEnv('ENDPOINT_FILE');
if (!endpointFile || !fs.existsSync(endpointFile)) {
  throw new Error('ENDPOINT_FILE variable missing or misconfigured: ' + file);
}

/**
 * get the RTC configuration JSON for this node/runtime
 * @param {string} [clientId] optional user/client id for the credentials
 */
function getRTCPeerConfig (clientId) {
  const { TURN_USER, TURN_PASS, TURN_SECRET } = getEnv();
  const port = getEnv('TURN_PORT', 3478);

  // determine credential type and create
  const cred = clientId ? getTURNCredentials(clientId, TURN_SECRET) : {
    username: TURN_USER,
    credential: TURN_PASS,
  };

  // get endpoints from the aggregator file
  const endpoints = JSON.parse(fs.readFileSync(endpointFile).toString());

  // format the stun/turn urls
  const urls = [].concat(...endpoints.map(addr => [
    `stun:${addr.ip}:${port}`,
    `turn:${addr.ip}:${port}?transport=udp`
  ]));

  // assemble expected payload
  return {
    iceTransportPolicy: 'all',
    iceServers: [{
      urls,
      ...cred,
    }],
  };
};

module.exports = {
  getRTCPeerConfig,
}