ARG NGINX_VERSION=1.25
FROM nginx:$NGINX_VERSION

COPY nginx/nginx.conf.template /etc/nginx/nginx.conf.template
COPY nginx/entrypoint.sh /

ENV CITY_SERVICE_URL=http://city-service:8080
ENV WEATHER_SERVICE_URL=http://weather-service:8080
ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
