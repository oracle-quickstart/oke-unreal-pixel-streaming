#!/bin/sh
# ----------------------------------------------------------------------
# Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------

export INTERNAL_IP="${INTERNAL_IP:-$(ip a | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)}"

# Determine external ip address
export EXTERNAL_IP="${EXTERNAL_IP:-$(dig +short myip.opendns.com @resolver1.opendns.com)}"

# (TODO: Remove in favor of auth secret/credentials)
turnadmin -a \
  -u ${TURN_USER:-turn} \
  -p ${TURN_PASS:-change} \
  -r ${TURN_REALM:-example.com}

# Start coturn server with options
# @see https://github.com/coturn/coturn/blob/master/README.turnserver
turnserver -n --no-cli \
  --verbose \
  --listening-port=${TURN_PORT:-3478} \
  --relay-ip="${INTERNAL_IP}" \
  --listening-ip="${INTERNAL_IP}" \
  --external-ip="${EXTERNAL_IP?missing external ip}/${INTERNAL_IP}" \
  --server-name=${TURN_REALM:-example.com} \
  --fingerprint \
  --lt-cred-mech \
  --realm=${TURN_REALM:-example.com} \
  --user="${TURN_USER:-pixel}:${TURN_PASS:-changeme}" \
  --rest-api-separator=":" \
  --channel-lifetime=${TURN_CHANNEL_LIFETIME:-"-1"} \
  --min-port=${TURN_MIN_PORT:-49152} \
  --max-port=${TURN_MAX_PORT:-65535} ${EXTRA_ARGS}