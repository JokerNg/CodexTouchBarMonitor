# CodexTouchBarMonitor

CodexTouchBarMonitor 是一个专注 Touch Bar 的 macOS 工具，通过本机 Codex app-server 读取额度和 Token 用量，并持续显示在 Touch Bar 上。菜单栏仅作为控制入口，不显示额度。

项目维护者：[JokerNg](https://github.com/JokerNg)

## 功能

- 菜单栏仅保留控制图标，不显示额度。
- 启动时隐藏 Dock 图标。
- Touch Bar 持续显示 5 小时额度、周额度、剩余百分比和重置时间；Pro 账户无 5 小时限制时仅显示周额度。
- 显示 Codex 官方 Token 用量，包括昨日用量和账户累计用量。
- 每 60 秒自动刷新，刷新失败时保留已有数据。
- 点击 Codex 图标可立即刷新；刷新徽标旋转，成功显示青色勾，失败或超时显示红色感叹号。
- app-server 连接失败或进程退出后自动重连，并显示连接状态和最后更新时间。
- 重置卡在最早可用卡到期前 3 天内显示为红色。
- 点击右侧区域可在重置卡、半年（26 周）Token 用量热力图和今日估算费用之间切换。
- 热力图使用 0 档深灰和 5 档固定用量：1–2500 万、2500–5000 万、5000–7500 万、7500 万–1 亿、1 亿以上；格子为正方形。
- 自动跳过不可用页面；默认记住上次页面，也可在菜单中选择固定页面或每 10 秒自动轮播。
- 本地统计今日与昨日的 Token 和估算费用，显示缓存输入占比；每分钟、手动刷新、跨日及唤醒时更新。
- Pro 账户使用带 PRO 标识的周限额布局，用量条与重置时间右侧对齐，昨日和累计用量分两行显示。
- 菜单支持“跟随系统 / 中文 / English”语言设置，选择后立即应用并持久保存。
- 自动跟随 ChatGPT / Codex 启动和退出。
- 支持从菜单隐藏 Touch Bar 或隐藏菜单栏图标。

## 数据来源

额度和官方 Token 用量通过本机 Codex app-server 获取，不抓网页、不要求填写 API Key：

```text
account/rateLimits/read
account/usage/read
```

本地费用统计递归读取 `~/.codex/sessions/` 中的 JSONL，按本地日期和模型汇总。价格来自 [LiteLLM 公开价格表](https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json)，每天更新并缓存在 `~/Library/Caches/CodexTouchBarMonitor/litellm-prices.json`。

金额是按当前 API 价格计算的美元估算，并非 Codex 订阅账单。`codex-auto-review` 按 `gpt-5.6-luna` 估算；无匹配价格时显示未知。今日费用与昨日全天比较；缓存命中率为缓存输入 Token 占全部输入 Token 的比例。

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
- 当前 Homebrew/DMG 发布包为 Apple Silicon（arm64）版本。
- 已安装 ChatGPT、Codex 或 GPT，并且本机 Codex app-server 可用。
- 需要配备实体 Touch Bar 的 Mac 才能使用。

## Touch Bar

应用启动后会以系统模态方式显示 Touch Bar 额度条，切换到其他窗口后仍会保留。

Touch Bar 包括：

- Codex 图标。
- 5 小时额度和周额度连续电量条。
- 剩余百分比、重置时间。
- 昨日 Token 用量和账户累计 Token 用量。
- 重置卡、半年 Token 用量热力图、今日估算费用和 Token（点击右侧区域切换）。

点击 Codex 图标会立即刷新数据。刷新期间徽标旋转，完成后短暂显示成功或失败状态。
右下角圆点表示当前可用页面。费用页以两行显示今日估算金额与 Token；逐模型明细、昨日对比及缓存命中率可在菜单查看。

持久 Touch Bar 使用 macOS 未公开的 AppKit 系统模态接口，不适合提交 Mac App Store；未来 macOS 更新可能改变该接口。

## 菜单栏菜单

点击菜单栏图标可以：

- 显示或隐藏 Touch Bar。
- 立即刷新数据。
- 重新加载 Touch Bar。
- 开关“随 Codex 自动启动”。
- 查看连接状态和最后更新时间。
- 设置界面语言：跟随系统、中文或 English。
- 设置 Touch Bar 默认页面：记住上次、自动轮播（10 秒），或固定页面。
- 查看今日本地用量、昨日全天费用对比、缓存命中率和各模型估算费用。
- 隐藏菜单栏图标；重新打开 App 可恢复。
- 退出应用。

## 构建和运行

构建 App：

```bash
scripts/build-app.sh
open build/CodexTouchBarMonitor.app
```

构建成功后会生成 `build/CodexTouchBarMonitor.app`。首次手动打开后，应用默认安装用户级 LaunchAgent，之后会随 ChatGPT / Codex 自动启动和退出；也可以从菜单关闭自动启动。

打包 DMG：

```bash
scripts/package-dmg.sh
```

输出文件为 `dist/CodexTouchBarMonitor-0.1.16.dmg`。当前构建使用 ad-hoc 签名，首次打开时 macOS 可能提示无法验证开发者；可在 Finder 中右键 App，选择“打开”。

开发期直接运行：

```bash
swift run
```

## Homebrew

发布版本后，可以通过自建 Tap 安装：

```bash
brew install --cask jokerng/tap/codex-touchbar-monitor
```

升级：

```bash
brew upgrade --cask jokerng/tap/codex-touchbar-monitor
```

## 重新生成 App 图标

图标源图为 `Resources/AppIcon.png`，生成 ICNS：

```bash
scripts/make-app-icon.py
```

## 隐私

CodexTouchBarMonitor 不保存密码、API Key、授权码或账号凭据。额度来自本机 Codex app-server，会话日志在本机解析；网络请求仅用于下载公开价格表，不上传会话内容或用量数据。

## 许可证

本项目采用 MIT License，详见 [LICENSE](LICENSE)。
