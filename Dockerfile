FROM ghcr.io/cirruslabs/flutter:3.44.0 AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

ARG MAPTILER_API_KEY
ARG PUBLIC_TRACE_BASE_URL
ARG ONLINE_BASE_TILE_URL_TEMPLATE
ARG ONLINE_SATELLITE_TILE_URL_TEMPLATE

RUN flutter build web --release --no-wasm-dry-run \
    --dart-define=MAPTILER_API_KEY=${MAPTILER_API_KEY} \
    --dart-define=PUBLIC_TRACE_BASE_URL=${PUBLIC_TRACE_BASE_URL} \
    --dart-define=ONLINE_BASE_TILE_URL_TEMPLATE=${ONLINE_BASE_TILE_URL_TEMPLATE} \
    --dart-define=ONLINE_SATELLITE_TILE_URL_TEMPLATE=${ONLINE_SATELLITE_TILE_URL_TEMPLATE}

FROM nginx:1.27-alpine

COPY --from=build /app/build/web /usr/share/nginx/html
COPY render/nginx.conf.template /etc/nginx/templates/default.conf.template

EXPOSE 10000
