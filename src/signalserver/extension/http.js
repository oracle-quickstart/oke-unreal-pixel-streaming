/**
 * Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
 * The Universal Permissive License (UPL), Version 1.0
 */
const http = require('http');
const https = require('https');

/**
* Map of header names used in auth/signing
*/
const HEADERS = {
  AUTHORIZATION: 'authorization',
  HOST: 'host',
  DATE: 'date',
  TARGET: '(request-target)',
  CONTENT_TYPE: 'content-type',
  CONTENT_LENGTH: 'content-length',
  CONTENT_HASH: 'x-content-sha256',
};

class HttpClient {

  constructor(baseUrl) {
    this.baseUrl = (baseUrl || '').replace(/\/$/, '');
  }

  _url(url) {
    let u = url;
    if (!/^http/.test(url)) {
      u = [this.baseUrl, u].filter(Boolean)
        .map(p => p.replace(/^\//, '')).join('/');
    }
    return new URL(u);
  }

  /**
   * alter the request object pre-flight
   * @private
   * @param {https.Request} request 
   * @param {*} [body]
   * @returns {void}
   */
  _precondition(request, body) {

  }

  /**
   * Make an https request
   * @param {string} url - Https API URL
   * @param {https.RequestOptions} [options] - https request options @see https://nodejs.org/api/https.html#https_https_request_url_options_callback
   * @param {object} [options.body] - Optional body of request to be sent
   * @param {object} [options.query] - Optional object for query string params
   * @returns {Promise<response>}
   */
  request(url, options) {
    return new Promise((resolve, reject) => {
      // process options
      options = options || {};
      let { body, query } = options;

      // setup request
      const reqUrl = this._url(url);
      if (!!query) {
        reqUrl.searchParams = new URLSearchParams(query);
      }

      // start request
      const sender = reqUrl.protocol === 'http:' ? http : https;
      const request = sender.request(reqUrl, options, response => {
        let data = '';
        // hanlde response
        response
          .on('data', chunk => data += chunk)
          .on('end', () => {
            const { headers, statusCode } = response;
            // parse json
            if (headers['content-type'] === 'application/json') {
              data = JSON.parse(data);
            }
            const res = { statusCode, headers, data };
            // handle Promise resolution
            if (/^2/.test(statusCode)) {
              resolve(res);
            } else {
              const err = new Error(`${response.statusCode}: ${response.statusMessage}`);
              err.response = res;
              reject(err);
            }
          })
      }).on('error', reject);

      // handle body
      if (body) {
        if (typeof body === 'object' && !(body instanceof Buffer)) {
          body = JSON.stringify(body);
          request.setHeader(HEADERS.CONTENT_TYPE, 'application/json');
        }
        request.setHeader(HEADERS.CONTENT_LENGTH, body.length);
      } else if (['POST', 'PUT', 'PATCH'].includes(request.method)) {
        request.setHeader(HEADERS.CONTENT_TYPE, 'application/json');
        request.setHeader(HEADERS.CONTENT_LENGTH, 0);
      }


      // precondition & send
      this._precondition(request, body);
      request.end(body || undefined);
    });
  }

  /**
   * HEAD convenience
   */
  head(url, options) {
    return this.request(url, Object.assign({ method: 'HEAD'}, options));
  }

  /**
   * GET convenience
   */
  get(url, options) {
    return this.request(url, Object.assign({ method: 'GET'}, options));
  }

  /**
   * DELETE convenience
   */
  delete(url, options) {
    return this.request(url, Object.assign({ method: 'DELETE' }, options));
  }

  /**
   * POST convenience
   */
  post(url, data, options) {
    return this.request(url, Object.assign({ method: 'POST', body: data }, options));
  }

  /**
   * PUT convenience
   */
  put(url, data, options) {
    return this.request(url, Object.assign({ method: 'PUT', body: data }, options));
  }

  /**
   * PATCH convenience
   */
  patch(url, data, options) {
    return this.request(url, Object.assign({ method: 'PATCH', body: data }, options));
  }
}

module.exports = {
  HEADERS,
  HttpClient,
};
