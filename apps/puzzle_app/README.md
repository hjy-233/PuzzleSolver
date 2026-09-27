# PuzzleSolver Web 前端

基于 Flutter Web 的网格谜题界面。目前实现数回（Slitherlink）：支持生成题目、手动录入、游玩、提示、自动求解、检查答案和回看推理步骤。

## 本地运行

```sh
flutter pub get
flutter run -d web-server
```

生成失败时会自动重试直到成功。生成、求解和答案检查均由浏览器本地执行；默认不会请求服务端 API。浏览器上的计算可能短暂占用界面线程。

## 分享链接

数回页面地址为 `/slitherlink`。分享菜单可以复制仅含页面地址的链接、当前题目链接，或包含当前线/叉进度的题目链接。题目和进度都保存在 URL 中，不写入服务器存档。

前端完全不调用服务端 API。可选 API 仅供获邀的直接调用者使用，需附加 `Authorization: Bearer <邀请码>`。邀请码保存在部署数据卷 `/app/data/invitation-code.txt`，永久有效且不会自动轮换；获准请求仍受每 IP 每分钟限流及服务资源上限约束。不要把邀请码写入浏览器前端、分享链接或公开仓库。本项目根目录的 `Dockerfile` 会构建前端和服务端。
