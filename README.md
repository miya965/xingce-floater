# 行测悬浮刷题器

macOS 桌面上的一个小悬浮窗。收起时是一枚可拖动的小羊，点开是一张 260×320 的答题卡。选中选项后提交，再看解析。窗口保持在最前。

本项目是独立程序，不是 [考公刷题](https://github.com/ERRRC/kaogong-shuati) 的官方客户端。感谢 [@ERRRC](https://github.com/ERRRC) 维护那个项目。

## 功能

- 48×48 的小羊按钮，可拖动，并记住位置
- 小卡片答题：科目、题型、题干、选项、提交、上一题、下一题、解析
- 提交前可以改选项，提交后锁定，并区分答对和答错
- 卡片处于焦点时，A/B/C/D 选择，Enter 提交，Esc 收起
- 全局热键只有 Control+Option+Q，用来显示或隐藏悬浮窗
- 可选连接本机已经运行的刷题服务（`127.0.0.1:3927`），现取现显示，成绩写回该服务
- 仓库自带少量原创示例题，供没有本地服务时理解数据格式

## 环境

- macOS 12 或更高
- Xcode Command Line Tools（`swiftc`、`xcrun`）
- 架构按本仓库脚本为 `x86_64-apple-macos12.0`

只构建和运行悬浮窗时，不需要 Node.js，也不需要第三方题库。

## 构建

```bash
bash scripts/run-tests.sh
bash scripts/build-app.sh
```

生成的应用在 `build/行测刷题器.app`。`build/` 已忽略，不会进入 Git。打开应用由你自己决定，脚本不会自动弹出窗口。

## 题库来源与版权

本仓库里的 `Fixtures/sample-bank.json` 是原创示例，不是国考或省考真题，也不是任何第三方题库的副本。它可以随本项目的 MIT 许可一起分发。

悬浮窗也可以连接用户自己在本机运行的刷题服务。当前识别的是 [ERRRC/kaogong-shuati](https://github.com/ERRRC/kaogong-shuati)。那个项目的程序代码是 MIT 许可；它的题库数据（`tiku.db`、`materials.db` 和题目配图）不在 MIT 范围内，版权归粉笔等来源方，只授权随该仓库分发，供个人学习，不得商用或二次分发。

本项目不包含、也不重新分发这些题库、题干、选项、答案、解析和配图。详情见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

要连接该服务，先按它自己的说明在本机准备好目录，然后任选一种方式告诉本程序：

1. 环境变量 `XINGCE_PRACTICE_ROOT` 指向包含 `server.mjs` 的目录。
2. 在本仓库目录放置 `practice-root.local`，内容为该目录的路径。可参考 `practice-root.local.example`。此文件已被忽略。
3. 把该目录放在本仓库的同级，并命名为 `kaogong-shuati`。
4. 若服务已经在 `127.0.0.1:3927` 监听，悬浮窗会直接使用，不再启动新进程。

Node 可执行文件按 `XINGCE_NODE`、系统 `PATH`、本机应用支持目录中的 `node-runtime` 依次查找。本仓库不附带 Node 运行时。

## 许可证

本仓库自己的源码、原创示例和 Cursor Skill 使用 [MIT License](LICENSE)。Copyright (c) 2026 miya965。

这项许可不覆盖第三方题库，也不把别人的题库重新授权出去。

## Cursor Skill

给 Cursor 代理用的项目说明在 `.cursor/skills/xingce-floater/`。
