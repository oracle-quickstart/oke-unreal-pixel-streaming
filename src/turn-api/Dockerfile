# ----------------------------------------------------------------------
# Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------

FROM --platform=${BUILDPLATFORM:-linux/amd64} node:14-alpine

# Move to app dir
WORKDIR /app

# install
COPY . .
RUN npm ci

CMD ["node", "main.js"]