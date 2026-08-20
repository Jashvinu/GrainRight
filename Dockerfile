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

# WhatsApp's in-app browser can keep an old main.dart.js for days.  Generate a
# separate bootstrap that references this build through a unique query string,
# so the boundary capability link cannot launch the cached login application.
RUN boundary_build_id=$(sha256sum build/web/main.dart.js | awk '{print substr($1, 1, 16)}') \
    && sed "s|main.dart.js|main.dart.js?v=${boundary_build_id}|g" \
      build/web/flutter_bootstrap.js > build/web/whatsapp-boundary-bootstrap.js \
    && sed "s|__WHATSAPP_BOUNDARY_BUILD_ID__|${boundary_build_id}|g" \
      render/whatsapp-boundary.html.template > build/web/whatsapp-boundary.html

FROM nginx:1.27-alpine

COPY --from=build /app/build/web /usr/share/nginx/html
COPY render/nginx.conf.template /etc/nginx/templates/default.conf.template

EXPOSE 10000
