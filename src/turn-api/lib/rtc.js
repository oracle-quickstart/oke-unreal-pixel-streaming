/**
 * Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
 * The Universal Permissive License (UPL), Version 1.0
 */
const fs = require('fs');
const { getEnv } = require("./env")
const { getTURNCredentials } = require("./cred");

const endpointFile = getEnv('ENDPOINT_FILE');
if (!endpointFile || !fs.existsSync(endpointFile)) {
  // hard fail when the file is not configured
  throw new Error('ENDPOINT_FILE variable missing or misconfigured: ' + file);
}

function readEndpointJSON() {
  return new Promise((resolve, reject) => 
    fs.readFile(endpointFile, (err, data) =>
      err ? reject(err) : resolve(JSON.parse(data.toString()))
    )
  );
}

/**
 * get the RTC configuration JSON for this node/runtime
 * @param {string} [clientId] optional user/client id for the credentials
 * @returns {Promise<object>} 
 */
function getRTCPeerConfig(clientId) {
  const { TURN_USER, TURN_PASS, TURN_SECRET } = getEnv();
  const port = getEnv('TURN_PORT', 3478);

  // determine credential type and create
  const cred = clientId ? getTURNCredentials(clientId, TURN_SECRET) : {
    username: TURN_USER,
    credential: TURN_PASS,
  };

  // resolve the endpoints then format into the RTC config
  return readEndpointJSON().then(endpoints => {
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
  });
  
};

module.exports = {
  getRTCPeerConfig,
};
