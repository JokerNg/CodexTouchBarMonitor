# CodexTouchBarMonitor

CodexTouchBarMonitor 是一个专注 Touch Bar 的 macOS 工具，通过本机 Codex app-server 读取额度和 Token 用量，并持续显示在 Touch Bar 上。菜单栏仅作为控制入口，不显示额度。

项目维护者：[JokerNg](https://github.com/JokerNg)

## 功能

- 菜单栏仅保留控制图标，不显示额度。
- Touch Bar 持续显示 5 小时额度、周额度、剩余百分比和重置时间。
- 显示 Codex 官方 Token 用量，包括昨日用量和账户累计用量。
- 每 60 秒自动刷新，刷新失败时保留已有数据。
- 自动跟随 ChatGPT / Codex 启动和退出。
- 支持从菜单隐藏 Touch Bar 或隐藏菜单栏图标。

## 数据来源

应用不抓网页、不要求填写 API Key，只调用本机 Codex app-server：

```text
account/rateLimits/read
account/usage/read
```

应用会自动查找以下 Codex 可执行文件：

```text
/Applications/ChatGPT.app/Contents/Resources/codex
/Applications/Codex.app/Contents/Resources/codex
/Applications/GPT.app/Contents/Resources/codex
```

## 来源与致谢

本项目基于 Jack Chen 的开源项目 [TouchBarCodexToken](https://github.com/jackchensky/TouchBarCodexToken) 二次开发，保留原项目的 MIT 版权声明。

## 兼容性

- macOS 11 Big Sur 或更新版本。
- 已安装 ChatGPT、Codex 或 GPT，并且本机 Codex app-server 可用。
- 需要配备实体 Touch Bar 的 Mac 才能使用。

## Touch Bar

应用启动后会以系统模态方式显示 Touch Bar 额度条，切换到其他窗口后仍会保留。

Touch Bar 包括：

- Codex 图标。
- 5 小时额度和周额度连续电量条。
- 剩余百分比、重置时间。
- 昨日 Token 用量和账户累计 Token 用量。

持久 Touch Bar 使用 macOS 未公开的 AppKit 系统模态接口，不适合提交 Mac App Store；未来 macOS 更新可能改变该接口。

## 菜单栏菜单

点击菜单栏图标可以：

- 显示或隐藏 Touch Bar。
- 重新加载 Touch Bar。
- 隐藏菜单栏图标；重新打开 App 可恢复。
- 退出应用。

## 构建和运行

构建 App：

```bash
scripts/build-app.sh
open build/CodexTouchBarMonitor.app
```

构建成功后会生成 `build/CodexTouchBarMonitor.app`。首次手动打开后，应用会安装用户级 LaunchAgent，之后会随 ChatGPT / Codex 自动启动和退出。

打包 DMG：

```bash
scripts/package-dmg.sh
```

输出文件为 `dist/CodexTouchBarMonitor-0.1.12.dmg`。当前构建使用 ad-hoc 签名，首次打开时 macOS 可能提示无法验证开发者；可在 Finder 中右键 App，选择“打开”。

开发期直接运行：

```bash
swift run
```

## 重新生成 App 图标

图标源图为 `Resources/AppIcon.png`，生成 ICNS：

```bash
scripts/make-app-icon.py
```

## 隐私

CodexTouchBarMonitor 不保存密码、API Key、授权码或账号凭据。额度数据来自本机 Codex app-server，只显示在本机 UI 中。

## 许可证

本项目采用 MIT License，详见 [LICENSE](LICENSE)。
