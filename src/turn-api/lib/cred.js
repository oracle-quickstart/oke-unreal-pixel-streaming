/**
 * Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
 * The Universal Permissive License (UPL), Version 1.0
 */
const crypto = require('crypto');

// must match the separator specified as --rest-api-separator in the coturn runtime
const SEPARATOR = ':';

/**
 * generate a 
 * @param {string} name 
 * @param {string} secret 
 * @returns {object}
 */
function getTURNCredentials(name, secret) {
  
  // this credential would be valid for the next 24 hours
  var unixTimeStamp = parseInt(Date.now() / 1000) + 24 * 3600, 
    username = [unixTimeStamp, name].join(SEPARATOR),
    password,
    hmac = crypto.createHmac('sha1', secret);
  hmac.setEncoding('base64');
  hmac.write(username);
  hmac.end();
  password = hmac.read();
  return {
    username: username,
    credential: password,
  };
}


module.exports = {
  getTURNCredentials,
};
