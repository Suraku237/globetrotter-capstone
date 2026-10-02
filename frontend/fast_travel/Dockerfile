FROM ubuntu:24.04 AS build

ARG FLUTTER_VERSION=3.44.1
ARG API_BASE_URL=https://fasttravel-web.duckdns.org/api

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git libglu1-mesa unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
        https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"

RUN flutter config --no-analytics \
    && flutter precache --web

WORKDIR /app
COPY . .
RUN flutter pub get \
    && flutter build web --release --no-tree-shake-icons \
        --dart-define="API_BASE_URL=${API_BASE_URL}"

FROM nginx:1.28-alpine AS runtime

COPY deploy/docker.nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1/healthz || exit 1
