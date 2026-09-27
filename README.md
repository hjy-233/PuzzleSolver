# PuzzleSolver

一个用于网格逻辑谜题的 Dart 平台。谜题由棋盘拓扑、谜题专属状态和规则组成。

## 项目结构

- `packages/puzzle_core`：纯 Dart 核心，不依赖 Flutter 或服务器。提供统一的格子、边、交点标识，矩形棋盘拓扑、交互动作、可撤销/重做的操作记录、结构化推理步骤，以及数回参考实现。
- `apps/puzzle_app`：Flutter Web 前端。目前提供数回生成、游玩、录入、提示、自动求解、答案检查和步骤回放；生成和求解由浏览器本地执行。
- `deploy`：Dart HTTP 服务。负责静态网页托管以及可选的数回生成、求解和检查 API。

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

谜题和游玩进度由分享链接携带，不保存在服务器数据库中。网页生成、求解、提示和检查都由用户浏览器执行，服务不参与前端计算。服务仍保留可选 API，需要持久化数据卷保存邀请码和每日额度日志。

## 可选 API 与邀请码

前端不会请求服务端 API。获邀用户直接调用 API 时，必须在请求中发送 `Authorization: Bearer <邀请码>`。邀请码首次生成后持久保存在数据卷 `/app/data/invitation-code.txt`，不会自动过期或轮换；请私下发放，切勿写进前端代码、公开链接或仓库。

API 缺少有效 Bearer 邀请码时返回 401。获准请求仍受每 IP 每分钟限流和服务器并发/资源上限约束。可以在 ProjectDeployer 的容器日志或数据卷中获取管理员侧的邀请码。

## 授权协议

本项目使用 MIT License，详见 [`LICENSE`](LICENSE)。
