# ---- Build stage -----------------------------------------------------
# Compiles both the release web bundle and a debug Android APK. Using the
# Cirrus Labs Flutter image (bundles Flutter + Android SDK + Java) means the
# VPS itself never needs Flutter/Android tooling installed — only Docker.
FROM ghcr.io/cirruslabs/flutter:3.24.3 AS build
WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build web --release \
 && flutter build apk --debug

# ---- Runtime stage -----------------------------------------------------
# Plain nginx serving the web bundle, with the APK dropped alongside it as
# a direct download (no Play Store / signing infra yet — see the "APK
# signing" note in the deploy docs before shipping a release build).
FROM nginx:1.27-alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY --from=build /app/build/app/outputs/flutter-apk/app-debug.apk \
    /usr/share/nginx/html/downloads/fast-travel.apk
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
