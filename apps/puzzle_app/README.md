# PuzzleSolver Web 前端

基于 Flutter Web 的网格谜题界面，目前提供数回（Slitherlink）和数独（Sudoku）。两者均支持生成题目、手动录入、游玩、提示、自动求解、检查答案、回看推理步骤、撤销/重做及 URL 分享。

## 本地运行

```sh
flutter pub get
flutter run -d web-server
```

数回生成遇到随机候选不唯一时会重试；数独支持 6×6 与 9×9，难度分为简单（Single）、普通（Pair）和困难（Box-Line/矛盾排除）。生成、求解和答案检查均由浏览器本地执行；不会请求服务端 API。浏览器上的计算可能短暂占用界面线程。

## 分享链接

数回和数独页面地址分别为 `/slitherlink`、`/sudoku`。分享菜单可以复制谜题页、当前题目，或包含当前数字/线/叉和候选笔记进度的链接。题目和进度都保存在 URL 中，不写入服务器存档。

前端完全不调用服务端 API。可选 API 仅供获邀的直接调用者使用，需附加 `Authorization: Bearer <邀请码>`。邀请码保存在部署数据卷 `/app/data/invitation-code.txt`，永久有效且不会自动轮换；获准请求仍受每 IP 每分钟限流及服务资源上限约束。不要把邀请码写入浏览器前端、分享链接或公开仓库。本项目根目录的 `Dockerfile` 会构建前端和服务端。
