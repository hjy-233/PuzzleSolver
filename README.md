# PuzzleSolver

一个用于网格逻辑谜题的 Dart 平台。谜题由棋盘拓扑、谜题专属状态和规则组成。

## 项目结构

- `packages/puzzle_core`：纯 Dart 核心，不依赖 Flutter 或服务器。提供统一的格子、边、交点标识，矩形棋盘拓扑、交互动作、可撤销/重做的操作记录、结构化推理步骤，以及数回参考实现。
- `apps/puzzle_app`：Flutter Web 前端。目前提供数回的生成、游玩、录入、提示、自动求解、答案检查和步骤回放。
- `deploy`：Dart HTTP 服务。负责静态网页托管以及数回生成、求解和检查 API。

## 本地开发

运行核心测试：

```sh
cd packages/puzzle_core
dart format --set-exit-if-changed lib test
dart analyze
dart test
```

运行 Flutter Web 前端：

```sh
cd apps/puzzle_app
flutter pub get
flutter run -d web-server
```

## 部署

根目录的 `Dockerfile` 会构建 Flutter Web 页面和 Dart 服务。`project-deployer.json` 用于在 64 位 Raspberry Pi OS（ARM64）上通过 ProjectDeployer 部署；应用监听容器内的 8080 端口，并映射到主机的 18082 端口。

当前服务无状态，不需要持久化卷或密钥。谜题和游玩进度由分享链接携带，不保存在服务器数据库中。

## 授权协议

本项目使用 MIT License，详见 [`LICENSE`](LICENSE)。
