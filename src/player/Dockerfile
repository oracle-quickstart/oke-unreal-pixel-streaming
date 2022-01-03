# ----------------------------------------------------------------------
# Copyright (c) 2021, 2022 Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------

###############################
# Webserver container (nginx) #
###############################
FROM nginx:alpine as web

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY /web /usr/share/nginx/html

EXPOSE 8080
EXPOSE 8888