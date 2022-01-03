#!/bin/sh
# ----------------------------------------------------------------------
# Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------

# determine nameserver for resolving in docker/k8s
export NS_RESOLVER="${NS_RESOLVER:-$(cat /etc/resolv.conf | grep ^nameserver | awk '{print $2}' | head -n 1)}"
echo "NS Resolver: ${NS_RESOLVER}"

# process the header configuration into nginx variable format
export PROXY_HEADER_NAME=$(echo "${PROXY_HEADER_NAME:-X-Proxy}" | tr '[:upper:]' '[:lower:]' | tr '-' '_' )

# apply variables to template
envsubst '
\$NS_RESOLVER
\$PROXY_HEADER_NAME' < /etc/nginx/conf.d/default.conf.tmpl > /etc/nginx/conf.d/default.conf
echo "Configured nginx"

#start nginx
echo "Starting nginx"
nginx -g 'daemon off;'
