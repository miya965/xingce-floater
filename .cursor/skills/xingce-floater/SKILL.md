---
name: xingce-floater
description: >-
  Maintain the macOS 行测 floating quiz app (XingceFloater): small sheep button,
  compact 260×320 card, local practice service, and original sample questions.
  Use when editing this floater, its card layout, hotkeys, SQLite bank, or the
  localhost practice client. Do not copy or publish third-party exam text.
---

# 行测悬浮刷题

个人用的 macOS 悬浮窗。小羊收起，点开是小卡片。题目可以来自本程序自带的原创示例，或用户本机已经在跑的刷题服务。第三方题库只在那台机器的服务里，不进本仓库。

## 不能做的事

- 不把第三方题库、解析、配图抄进本仓库、Fixtures、sqlite 或提交记录。
- 不把题干、选项、解析写进聊天、日志或测试输出。检查接口时只看字段名、题量和 HTTP 状态。
- 不把第三方题库打进 skill 包或 GitHub 发布物。
- 验证界面时不要再弹出测试窗口。用 `scripts/run-tests.sh` 和 `scripts/build-app.sh`。用户自己打开 `build/行测刷题器.app`。

## 机器限制

本机是 macOS 12、x86_64、只有 Command Line Tools。目标 `x86_64-apple-macos12.0`。不要用 macOS 13 才有的 SwiftUI API。应用入口是 AppKit `@main`，编译必须带 `-parse-as-library`。测试脚本不要加这个参数。

## 界面

- 收起：48×48 小羊，能拖，位置记住。点一下打开卡片，拖动不打开。
- 卡片：宽 260、高 320，题干和选项约 12 号字。见 `FloaterMetrics`。
- 收起按钮和 Esc 回到小羊。唯一全局热键是 Control+Option+Q。
- 窗口置顶。卡片是本程序的小卡片，不用对方网页整页塞进窗口。

## 题目从哪来

1. 用户本机服务已在听 `127.0.0.1:3927` 时，现取现显示，提交记到那个服务自己的成绩。一次大约 8 题，最后一题再按下一题才再取。
2. 服务目录用 `XINGCE_PRACTICE_ROOT`、`practice-root.local` 或同级目录 `kaogong-shuati` 查找。源码里不要写某台电脑的绝对路径。
3. 服务没开时，卡片说明服务没启动。不要悄悄改回只显示仓库里的示例，以免用户以为题库只有几道。
4. 仓库里的 `Fixtures/sample-bank.json` 是原创示例，可随代码发布。它不是真题，也不是第三方题库。

纯图片、转不出文字的题不进小卡片。

## 构建

```bash
bash scripts/run-tests.sh
bash scripts/build-app.sh
```

生成物是 `build/行测刷题器.app`，目录已在 `.gitignore`。不要把 `.app`、Node 运行时或本机题库目录提交上去。

## 发布

GitHub 上只放本仓库源码、原创示例、这份 skill。发布前确认状态里没有 `tiku.db`、题库分卷、解析导出或别人的题目 JSON。
