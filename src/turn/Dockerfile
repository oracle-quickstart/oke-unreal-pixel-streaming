# ----------------------------------------------------------------------
# Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------
FROM --platform=${BUILDPLATFORM:-linux/amd64} alpine:3.15

# add dependencies
RUN apk update && \
  apk add -u --no-cache bind-tools coturn

# set entrypoint script
COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]