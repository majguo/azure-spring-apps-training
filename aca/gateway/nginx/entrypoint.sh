#!/usr/bin/env sh
set -eu

envsubst '${PORT} ${CITY_SERVICE_URL} ${WEATHER_SERVICE_URL}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

exec "$@"