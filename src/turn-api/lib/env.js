/**
 * Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
 * The Universal Permissive License (UPL), Version 1.0
 */
const { env } = process;

function getEnv(key, fallback) {
  return key ? (env[key] || fallback) : {...env};
}

module.exports = {
  getEnv,
};
