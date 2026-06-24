# CodexBar

一个原生 macOS 快捷工具：按下全局快捷键，选择工作目录，输入任务并直接运行 Codex。

## 当前功能

- Spotlight / HapiGo 风格浮层
- 左侧工作目录列表
- 后台 `codex exec --json` + Agent 时间线输出 + 停止
- Terminal 交互模式
- 自动检测 Codex CLI / 手动指定路径
- 多任务并行、任务中心和最近任务复用
- 菜单栏常驻
- 输出按消息、思考、命令、文件变更、计划、MCP、搜索和错误分块展示
- 输出默认跟随并滚动到底部；向上查看时提供“回到底部”按钮
- 默认执行方式：后台模式
- 输入框支持 `⌘A`、`⌘C`、`⌘X`、`⌘V`、`⌘Z`、`⌘⇧Z`
- 默认快捷键：`⌥ Space`

详细范围见 [`docs/MVP_SCOPE.md`](docs/MVP_SCOPE.md)。

## 环境

- macOS 13+
- Xcode 15+ 或 Swift 5.9+
- 已安装并登录 Codex CLI

先在 Terminal 验证：

```bash
codex --version
```

## 运行方式 A：Xcode

1. 打开 `CodexBar.xcodeproj`
2. 选择 `My Mac`
3. Run

工程关闭 App Sandbox，适合本地开发与 Developer ID 直装分发。

## 运行方式 B：命令行构建 App

```bash
./scripts/build_app.sh
```

生成：

```text
build/CodexBar.app
```

安装到 Applications：

```bash
./scripts/install_app.sh
```

## 使用

1. 按 `⌥ Space` 打开。
2. 左侧添加或选择项目目录。
3. 选择执行方式：
   - **后台**：输入任务后按 Enter，结果以 Agent 时间线显示在任务中心。
   - **终端**：输入初始任务或留空，按 Enter 打开 Terminal 中的 Codex。
4. `Shift + Enter` 换行，`Esc` 关闭。

首次使用终端模式时，macOS 可能询问是否允许 CodexBar 控制 Terminal。

## 后台模式的安全策略

后台执行使用：

```text
codex --ask-for-approval never exec --cd <workspace> --sandbox workspace-write --json
```

这适合无需人工确认、且修改范围限制在当前工作目录内的任务。需要联网、跨目录访问或逐步审批时，切换到终端交互模式。

## 已知限制

- 当前快捷键使用预设列表，尚未做任意按键录制。
- Terminal 是首版唯一交互终端。
- Linux 容器无法链接 AppKit，因此本包只能在 macOS/Xcode 完成最终编译验证。

## 打包 DMG / PKG

创建本机使用的 DMG：

```bash
./scripts/package_dmg.sh
```

创建本机测试用 PKG：

```bash
./scripts/package_pkg.sh
```

面向其他用户分发时，需要 Developer ID 签名和 Apple 公证。完整命令见：

[`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md)
