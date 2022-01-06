# ----------------------------------------------------------------------
# Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------

###############################
#    Build stage (node/npm)   #
###############################
FROM --platform=${BUILDPLATFORM:-linux/amd64} node:14-alpine as builder

RUN npm config set loglevel warn \
  && npm set progress=false

# install dependencies
COPY package*.json /tmp/
RUN cd /tmp && npm ci
RUN mkdir -p /src && cp -a /tmp/node_modules /src
RUN rm -rf /tmp/node_modules

# copy source and build
WORKDIR /src
COPY . .
RUN npm prune --production

############################
# Runtime container (node) #
############################
FROM --platform=${TARGETPLATFORM:-linux/amd64} node:14-alpine
COPY --from=builder /src /app
WORKDIR /app

# entrypoint
ENTRYPOINT [ "node", "wrapper.js" ]
