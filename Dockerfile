FROM ghcr.io/cirruslabs/flutter:stable AS build

ENV FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
ENV PUB_HOSTED_URL=https://pub.flutter-io.cn

WORKDIR /workspace

COPY packages/puzzle_core/pubspec.yaml packages/puzzle_core/pubspec.lock ./packages/puzzle_core/
COPY apps/puzzle_app/pubspec.yaml apps/puzzle_app/pubspec.lock ./apps/puzzle_app/
COPY deploy/pubspec.yaml deploy/pubspec.lock ./deploy/
RUN cd apps/puzzle_app && flutter pub get && cd ../../deploy && dart pub get

COPY packages/puzzle_core ./packages/puzzle_core
COPY apps/puzzle_app ./apps/puzzle_app
RUN cd apps/puzzle_app && flutter build web --release --no-wasm-dry-run

FROM ghcr.io/cirruslabs/flutter:stable AS runtime

COPY deploy /app/deploy
COPY packages/puzzle_core /app/packages/puzzle_core
COPY --from=build /workspace/apps/puzzle_app/build/web /srv/puzzle-solver

EXPOSE 8080

WORKDIR /app/deploy
RUN dart pub get --offline

CMD ["dart", "run", "server.dart"]
