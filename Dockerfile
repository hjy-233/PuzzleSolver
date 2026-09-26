FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /workspace

COPY packages/puzzle_core/pubspec.yaml packages/puzzle_core/pubspec.lock ./packages/puzzle_core/
COPY apps/puzzle_app/pubspec.yaml apps/puzzle_app/pubspec.lock ./apps/puzzle_app/
RUN cd apps/puzzle_app && flutter pub get

COPY packages/puzzle_core ./packages/puzzle_core
COPY apps/puzzle_app ./apps/puzzle_app
RUN cd apps/puzzle_app && flutter build web --release --no-wasm-dry-run

FROM nginx:1.27-alpine

COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /workspace/apps/puzzle_app/build/web /usr/share/nginx/html

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
