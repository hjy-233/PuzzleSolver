FROM ghcr.io/cirruslabs/flutter:stable AS build

ENV FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

WORKDIR /workspace

COPY packages/puzzle_core/pubspec.yaml packages/puzzle_core/pubspec.lock ./packages/puzzle_core/
COPY apps/puzzle_app/pubspec.yaml apps/puzzle_app/pubspec.lock ./apps/puzzle_app/
RUN cd apps/puzzle_app && flutter pub get

COPY packages/puzzle_core ./packages/puzzle_core
COPY apps/puzzle_app ./apps/puzzle_app
RUN cd apps/puzzle_app && flutter build web --release --no-wasm-dry-run

FROM ghcr.io/cirruslabs/flutter:stable AS runtime

COPY deploy/server.dart /app/server.dart
COPY --from=build /workspace/apps/puzzle_app/build/web /srv/puzzle-solver

EXPOSE 8080

CMD ["dart", "/app/server.dart"]
