# puzzle_core

网格谜题的纯 Dart 核心包，不依赖 Flutter、后端服务，也不强制共享谜题状态模型。

## 通用能力

- 矩形棋盘拓扑，以及唯一的 `CellId`、`EdgeId`、`VertexId` 标识。
- 渲染命中目标和指针手势的通用模型。
- 支持撤销、重做和重放的不可变操作会话。
- 结构化推理步骤，可供界面本地化和逐步展示。

## 谜题专属能力

每种谜题自行定义状态、动作、规则、检查器和求解器。当前包括：

- 数回（Slitherlink）：边优先谜题，边状态独立于相邻格子。
- 数独（Sudoku）：支持 6×6（2×3 宫）与 9×9（3×3 宫），含唯一解生成、Single/Pair/Box-Line 推理及矛盾排除。

## 检查

```sh
dart format --set-exit-if-changed lib test
dart analyze
dart test
```
