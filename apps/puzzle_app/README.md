# PuzzleSolver Web 前端

基于 Flutter Web 的网格谜题界面。目前实现数回（Slitherlink）：支持生成题目、手动录入、游玩、提示、自动求解、检查答案和回看推理步骤。

## 本地运行

```sh
flutter pub get
flutter run -d web-server
```

## 分享链接

数回页面地址为 `/slitherlink`。分享菜单可以复制仅含页面地址的链接、当前题目链接，或包含当前线/叉进度的题目链接。题目和进度都保存在 URL 中，不写入服务器存档。

生成、求解和检查请求由 Dart 服务端处理；本项目根目录的 `Dockerfile` 会构建前端和服务端。
