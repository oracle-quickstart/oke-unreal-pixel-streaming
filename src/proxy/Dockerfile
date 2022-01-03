# ----------------------------------------------------------------------
# Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------

#################################
# NGINX dynamic proxy container #
#################################
FROM nginx:alpine as web

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/default.conf.tmpl /etc/nginx/conf.d/default.conf.tmpl
# set entrypoint script
COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh

EXPOSE 8080
EXPOSE 8888

ENTRYPOINT [ "/entrypoint.sh" ]