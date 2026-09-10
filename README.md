# DeepSeek Harness 开关（常驻状态型程序坞应用）

**简体中文** | [English](README.en.md)

**中文**：常驻程序坞的 DeepSeek Harness 开关 —— 左键点击回到/启动 dsh 网页界面，右键打开菜单（停止服务、动画开关）；图标实时显示服务与任务状态，并在任务完成或需要确认时发光提醒。

**English**: An always-on Dock toggle for DeepSeek Harness — left-click to open or start the dsh web UI, right-click for the menu (stop service, animation toggle). The icon mirrors live service/task state and glows when a task finishes or needs confirmation.

> 仓库：https://github.com/wjingshan/dsh-dock-launcher
>
> **[⬇️ 下载最新版（Release）](https://github.com/wjingshan/dsh-dock-launcher/releases/latest)** — 解压后把 App 拖进「应用程序」即可。

一个运行在 macOS（Apple Silicon / M4）上的**常驻**小程序：程序坞图标 = **拨动开关**。
**左键**点击 = 启动 / 回到 DeepSeek Harness（`dsh`）网页界面；**右键**点击 = 操作菜单（停止服务、动画开关等）。
图标实时呈现服务与任务状态，并在任务**完成 / 需要确认**时做动态提醒。

界面语言**跟随系统**，内置 简体中文 / English / 日本語 / 한국어（可在「系统设置 → 通用 → 语言与地区 → 应用程序」单独指定本 App 的语言）。

| 关闭 | 运行 · 空闲 | 任务进行中 | 任务完成 | 需要确认 |
|:--:|:--:|:--:|:--:|:--:|
| ![关闭](docs/icon-off.png) | ![运行](docs/icon-running.png) | ![进行中](docs/icon-busy.png) | ![完成](docs/icon-remind-complete.png) | ![需确认](docs/icon-remind-confirm.png) |
| 红 · 滑块在左 | 绿 · 滑块在右 | 多色极光流动 | 边缘内发光 + 白色流光 | 边缘内发光 + 白色流光 |

图标使用**连续圆角(squircle)** 并随系统浅/深色外观自动切换底板配色（下图左：深色外观；右：浅色外观）：

| 深色外观（默认） | 浅色外观 |
|:--:|:--:|
| ![深色](docs/icon-running.png) | ![浅色](docs/icon-light-appearance.png) |

## 一键安装

复制到「终端」执行，自动下载最新版并安装到 `/Applications`（含去除隔离标记、并自动启动）：

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/wjingshan/dsh-dock-launcher/main/install.sh)"
```

也可以手动安装：从 **[Releases](https://github.com/wjingshan/dsh-dock-launcher/releases/latest)** 下载 `.dmg`（打开后拖入「应用程序」）或 `.zip`（解压后拖入）。

> 首次打开若提示「无法验证开发者」：**右键 App → 打开**（或 系统设置 → 隐私与安全性 → 仍要打开）。

## 成品

```
DeepSeek Harness 开关.app   （当前版本 v0.13.0）
```

## 功能

- **程序坞左键 = 回到页面**：优先切回已打开的 `127.0.0.1:3080` 标签；页面被关了就恢复一个新标签；服务没运行则启动它。
- **程序坞右键 = 操作菜单**：打开页面 / 知道了(停止提醒) / **停止服务…（二次确认）** / **动画开关** / 打开日志 / 退出。
- **状态图标（4 态）**：
  - `关闭`（红，滑块左）= 服务已停止
  - `运行 · 空闲`（绿，滑块右）
  - `任务进行中`：多色极光流动（蓝→青→绿→紫长色带缓慢流动 + 一道柔光掠过，60fps）
  - `待关注提醒`：边缘向内呼吸发光 + 边缘内侧 2px 白色流光（沿边环绕）；完成=绿、需确认=橙
- **动态提醒**：任务完成 / 需要确认且你不在 dsh 页面时，图标先弹跳 4 次 + 通知 + 音效，随后转为**安静的持续发光**；等你**回到 dsh 页面**、点图标或菜单「知道了」即停止（不会周期性乱跳）。
- **动画总开关**：右键菜单可一键关闭/开启所有图标动画（关闭后为静态图标，弹跳与通知仍保留）；开销极低（仅动画态每帧重绘 128px 图标）。
- **自动注入 API key**：GUI 启动的进程不读 `.zshrc`，本 App 会自动解析 `~/.zshenv` / `.zprofile` / `.zshrc` / `.bash_profile` / `.bashrc` / `.profile` 中的 `DEEPSEEK_API_KEY` 注入 dsh 子进程（只读、不落盘、不外传）。
- **任务状态监测**：读取 `~/.dsh/sessions/*/session.jsonl.zstd` 活跃会话日志：
  - `approval/request`、`approval/asked` → **需要确认**
  - `turn/end`（普通对话回合结束）→ **任务完成**；存在活跃 goal 时回合结束不打扰，改为 `goal/change`（`operation == "complete"` / `goal.phase == "complete"`）→ **任务完成**
  - `turn/start` → **进行中**

> 完成提示规则：会话没有活跃 goal 时，一轮对话结束（`turn/end`）即算完成；会话存在活跃 goal 时，只在整个 goal 真正结束（`goal/change · complete`）时提示。监测覆盖所有近期活跃会话，多会话并行不漏检。

## 使用

1. 把 `DeepSeek Harness 开关.app` 拖进「应用程序」，双击打开（或拖到程序坞固定）。
2. App 启动时**如实显示服务状态**（未运行则显示红色「关闭」），**不会自动拉起 dsh**。
3. **左键**点程序坞图标 = 启动服务并打开 dsh 页面（已运行则回到页面）。
4. **右键**点程序坞图标 = 打开操作菜单（停止服务需二次确认）。
5. 菜单栏小图标点击可打开同一套菜单。

> 提示：首次使用请允许系统通知权限，才能收到「需要确认 / 任务完成」通知。

## 版本号规范

- 语义化版本，从 **0.1.0** 开始：
  - `patch`(+0.0.1) = 修 bug / 小改
  - `minor`(+0.1.0) = 新增功能 / 行为增强（0.x 阶段的主要改动也走 minor）
  - `major`(+1.0.0) = 重大改动 / 不兼容（进入稳定期后）
- `VERSION` = 语义版本号；`BUILD_NO` = 每次构建递增号（`build.sh` 自动生成，已 gitignore）。
- 每次改动在 `CHANGELOG.md` 追加记录。详见 `CHANGELOG.md`。

## 构建

```sh
cd dsh-dock-launcher
./build.sh          # 一键：绘图标→打包 icns→编译→组装→打包多语言→签名，并注入版本号
```

- 改图标颜色/造型：`src/Icons.swift`；改应用图标：`src/draw_icon.swift`。
- 改启动/监测/提示逻辑：`src/ServiceManager.swift`、`src/TaskMonitor.swift`、`src/main.swift`。
- 多语言文案：`resources/*.lproj/Localizable.strings`（en / zh-Hans / ja / ko）。

## 目录结构

```
dsh-dock-launcher/
├── src/
│   ├── main.swift          # 常驻应用：Dock/菜单栏、监测、动画、通知、左键回页面、右键菜单
│   ├── ServiceManager.swift# 启动/停止/端口探测、解析并注入 DEEPSEEK_API_KEY
│   ├── TaskMonitor.swift   # 多会话游标、zstd 解压、事件识别
│   ├── Frontmost.swift     # 前台浏览器/标签检测、聚焦或恢复 dsh 页面
│   ├── Icons.swift         # 各状态开关图标 + 菜单栏模板图标 + 动画绘制（极光/发光/流光）
│   └── draw_icon.swift     # 用 CoreGraphics 绘制 App 图标(生成 1024px PNG)
├── resources/              # 界面多语言（en / zh-Hans / ja / ko 的 Localizable.strings）
├── docs/                   # 状态图标预览图 + 支付宝收款码（README 引用）
├── install.sh              # 一键安装到 /Applications
├── Info.plist              # 应用元数据（含 CFBundleLocalizations）
├── build.sh                # 一键构建脚本（读取 VERSION/BUILD_NO 注入版本号）
├── VERSION                 # 语义版本号（第一行）
├── BUILD_NO                # 构建号（每次构建自增，已 gitignore）
├── CHANGELOG.md            # 版本记录
├── LICENSE                 # MIT
├── README.md / README.en.md    # 中文 / 英文说明
└── DeepSeek Harness 开关.app   # 成品（已 gitignore）
```

## 许可

[MIT](LICENSE) © 2026 wjingshan

---

## ☕ 赞助

`DeepSeek Harness 开关` 是我自用的小工具，顺手开源出来。如果它帮到了你，欢迎请我喝杯咖啡 ☕

<img src="docs/alipay-qr.jpg" alt="作者支付宝收款码（DeepSeek Harness 开关）" width="240" />

<div align="center">

**感谢你的支持！** 💙

</div>
