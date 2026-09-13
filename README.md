# DeepSeek Harness 开关（常驻状态型程序坞应用）

**简体中文** | [English](README.en.md)

**中文**：常驻程序坞的 DeepSeek Harness 开关 —— 左键点击回到/启动 dsh 网页界面，右键打开菜单（停止服务、动画开关）；图标实时显示服务与任务状态，并在任务完成或需要确认时发光提醒。

**English**: An always-on Dock toggle for DeepSeek Harness — left-click to open or start the dsh web UI, right-click for the menu (stop service, animation toggle). The icon mirrors live service/task state and glows when a task finishes or needs confirmation.

> 仓库：https://github.com/wjingshan/dsh-dock-launcher
>
> **[⬇️ 下载最新版（Release）](https://github.com/wjingshan/dsh-dock-launcher/releases/latest)** — 解压后把 App 拖进「应用程序」即可。

一个运行在 macOS（Apple Silicon / M4）上的**常驻**小程序：程序坞图标 = **拨动开关**。
**左键**点击 = 启动 / 回到 DeepSeek Harness（`dsh`）网页界面；**右键**点击 = 操作菜单（停止服务、动画开关等）。
图标实时呈现服务与任务状态，并在任务**完成 / 需要确认 / 等你选择**时做动态提醒。

界面语言**跟随系统**，内置 简体中文 / English / 日本語 / 한국어（可在「系统设置 → 通用 → 语言与地区 → 应用程序」单独指定本 App 的语言）。

| 图标 | 状态 | 说明 |
|:--:|:--|:--|
| ![关闭](docs/icon-off.png) | **关闭** | 红 · 滑块在左 |
| ![运行](docs/icon-running.png) | **运行 · 空闲** | 绿 · 滑块在右 |
| ![进行中](docs/icon-busy.gif) | **任务进行中** | 多色极光流动 |
| ![完成](docs/icon-remind-complete.gif) | **任务完成** | 边缘内发光 + 白色流光（绿） |
| ![需要确认/单选](docs/icon-remind-question.gif) | **需要确认 / 等你选择 · 单选** | 问号变形动画 |
| ![多选](docs/icon-remind-multi.gif) | **等你选择 · 多选** | 对勾淡化叠加 |

> 六张图放在**同一列**、而不是排成一行：GitHub 的 `max-width: 100%` 会把图片压缩到所在单元格的宽度。
> 横排时每列宽度都不同（实测 121～235px），每张图就被压成不同尺寸，看起来"大小不一"；放在同一列则
> 共用同一个列宽，无论视口多宽，六张图的显示尺寸必然完全一致。

> 上表里「任务进行中 / 任务完成 / 需要确认 · 单选 / 多选」都是**动图**。dsh 停下来等你选分支（`ask_user_question`）或审批计划（`exit_plan_mode`）时进入「需要你介入」态——**DeepSeek 与 HARNESS 分别向上下让开、开关上的白圆点放大成一个大圆角方形、里面浮现蓝色符号**，随后不停循环，**直到你在 dsh 页面做好选择、dsh 继续运算**，才播放**反向动画**收回成开关：
> - **需要确认（审批）· 等你选择 · 单选 / 普通提问**：圆内是蓝色**问号**，循环「亮度呼吸」（圆内蓝光一明一暗）。这几种情形**共用同一套问号动画**（所以表中并作一列），在 App 里的区别只在**提示音与通知文案**。
> - **多选**：圆内是蓝色**对勾**，循环「淡化叠加」——对勾从起点写出 → 画完从起点逐渐褪掉 → 还剩约一半时新一笔从起点重画，两笔同框。

图标使用**连续圆角(squircle)** 并随系统浅/深色外观自动切换底板配色（下图左：深色外观；右：浅色外观）：

| 深色外观（默认） | 浅色外观 |
|:--:|:--:|
| ![深色](docs/icon-running.png) | ![浅色](docs/icon-light-appearance.png) |

## ⚠️ 前置要求（别人装了却用不了，多半是这几条）

本 App 是 **DeepSeek Harness（`dsh`）的配套开关**，不是独立软件，请先满足：

1. **已安装 DeepSeek Harness**，`dsh` 命令可用，并至少运行过一次 `dsh web` 完成初始化（否则点图标会提示「未找到 dsh」）；
2. **`DEEPSEEK_API_KEY`**：在 `~/.zshrc` 里 `export DEEPSEEK_API_KEY=...`，或在 dsh 网页的 Models 页保存（否则 dsh 发消息会报 `no API key`）；
3. **（可选）`brew install zstd`**：任务状态监测与提醒需要它；缺失时 App 仍能启停服务，但图标不反映任务状态；
4. **系统要求**：macOS 14+，Apple Silicon 或 Intel（通用二进制）；
5. **首次打开**：本 App 未使用付费开发者证书签名/公证，若提示「无法验证开发者」或「已损坏」——
   **右键 App → 打开**，或执行：
   ```sh
   xattr -dr com.apple.quarantine "/Applications/DeepSeek Harness 开关.app"
   ```
   推荐直接用下面的**一键安装**（脚本会自动去掉隔离标记）。

App 菜单里也有 **「环境自检…」** 可以随时查看以上各项的实际状态与修复建议。

## 一键安装

复制到「终端」执行，自动下载最新版并安装到 `/Applications`（含去除隔离标记、并自动启动）：

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/wjingshan/dsh-dock-launcher/main/install.sh)"
```

也可以手动安装：从 **[Releases](https://github.com/wjingshan/dsh-dock-launcher/releases/latest)** 下载 `.dmg`（打开后拖入「应用程序」）或 `.zip`（解压后拖入）。

> 首次打开若提示「无法验证开发者」：**右键 App → 打开**（或 系统设置 → 隐私与安全性 → 仍要打开）。

## 成品

```
DeepSeek Harness 开关.app   （当前版本 v0.15.0）
```

## 功能

- **程序坞左键 = 回到页面**：优先切回已打开的 `127.0.0.1:3080` 标签；页面被关了就恢复一个新标签；服务没运行则启动它。打开的是**带 token 的完整地址**，因此不会落到 401 未授权页：优先读 dock-bridge 插件写的运行时文件，未装该插件时回退解析 dsh 启动日志。
- **程序坞右键 = 操作菜单**：打开页面 / 知道了(停止提醒) / **停止服务…（二次确认）** / **动画开关** / 打开日志 / 退出。
- **状态图标（4 态）**：
  - `关闭`（红，滑块左）= 服务已停止
  - `运行 · 空闲`（绿，滑块右）
  - `任务进行中`：多色极光流动（蓝→青→绿→紫长色带缓慢流动 + 一道柔光掠过，60fps）
  - `待关注提醒`：**需要你介入**（需确认 / 等你选择）= 变形动画（问号 / 对勾，见下）；**任务完成** = 绿色边缘内发光 + 边缘内侧 2px 白色流光
- **动态提醒**：需要确认 / **等你选择**时播放**变形动画**（0.9 秒变形 → 落定后循环 → 你做好选择后 0.42 秒反向收回成开关），并伴随弹跳 + 通知 + 提示音——**单选 / 普通提问**圆内是蓝色**问号**，循环「亮度呼吸」；**多选**圆内是蓝色**对勾**，循环「淡化叠加」（写出 → 从起点逐渐褪掉 → 还剩约一半时重写，两笔同框）；任务完成仍用绿色边缘发光。点图标、选「知道了」或把鼠标移到程序坞也会立即收回。
- **提示音可配置**（右键菜单 →「提示音设置…」打开**独立设置窗口**）：窗口里五种提示各占一行——需确认 / 等你选择 / 任务完成 / 服务启动 / 服务停止，每行可选音效（系统音效 + `~/Library/Sounds`）、可点试听按钮；三种提醒还能各自设置**重复次数**：`1` / `2` / `3` / `5` 次，或**「直到鼠标移到程序坞」**（鼠标进入程序坞或菜单栏区域即停，无需辅助功能权限）。底部还有「选择音效时自动试听」开关与「恢复默认」；设置持久化保存。
- **关于**：右键菜单「关于 …」显示软件名称、版本号（含 build 号）、GitHub 地址与赞助链接，可直接点按钮打开。
- **动画总开关**：右键菜单可一键关闭/开启所有图标动画（关闭后为静态图标，弹跳与通知仍保留）；开销极低（仅动画态每帧重绘 128px 图标）。
- **自动注入 API key**：GUI 启动的进程不读 `.zshrc`，本 App 会自动解析 `~/.zshenv` / `.zprofile` / `.zshrc` / `.bash_profile` / `.bashrc` / `.profile` 中的 `DEEPSEEK_API_KEY` 注入 dsh 子进程（只读、不落盘、不外传）。
- **任务状态监测**：读取 `~/.dsh/sessions/*/session.jsonl.zstd` 活跃会话日志：
  - `approval/request`、`approval/asked` → **需要确认**
  - `turn/end`（普通对话回合结束）→ **任务完成**；存在活跃 goal 时回合结束不打扰，改为 `goal/change`（`operation == "complete"` / `goal.phase == "complete"`）→ **任务完成**
  - `turn/start` → **进行中**
  - `tool/call` 且工具为 `ask_user_question` / `exit_plan_mode` → **等你选择**（这两类交互在日志里**没有**专用事件，只能按工具名识别）

> 完成提示规则：会话没有活跃 goal 时，一轮对话结束（`turn/end`）即算完成；会话存在活跃 goal 时，只在整个 goal 真正结束（`goal/change · complete`）时提示。监测覆盖所有近期活跃会话，多会话并行不漏检。

## 与同类插件的关系

dsh 生态里已有多个桌面启动器与提醒类项目，本 App 与它们的关键区别在**形态**：它不是 dsh 插件，而是一个独立的 macOS 原生程序坞应用——dsh 完全没有运行时，它照样在程序坞里待命，左键点一下就把服务拉起来并进入页面。

生态中的相关项目（名称与描述均可对照 [awesome-dsh-plugin 精选列表](https://github.com/awesome-dsh-plugin/awesome-dsh-plugin) 核实）：

| 相关项目 | 形态 | 与本 App 的差异 |
| --- | --- | --- |
| `dsh-start` | macOS，命令行 + 脚本生成可入坞的 `DSH.app` | 功能面同为 macOS 启停，但以 CLI 与脚本构建为主，App 需自行生成 |
| `dsh-launcher` | macOS，菜单栏应用 + 宿主插件写 `runtime.json` | 入口是**状态栏菜单**；本 App 的入口是**程序坞图标**本身 |
| `dsh-unread-dot` | macOS，Dock 角标与提示音 | 基于 Web 侧 Badging API，属 dsh 插件内部；本 App 是原生程序坞应用，自带图标动效 |
| `dsh-task-watcher-plugin` | Windows，托盘四态图标 + 任务面板 | 四态状态的思路接近，但只面向 Windows 托盘，且另起独立进程 |
| `dsh-tray`、`dsh-dock`、`dsh-native-launcher`、`dsh-desktop-windowos` | Windows 托盘 / 桌面壳 | 平台不同 |
| `dsh-clean-desktop-shell` | Windows + macOS 桌面壳 | 以快捷方式与托盘为主；不提供程序坞图标即状态显示 |

本 App 的组合目前没有第二个项目同时具备：**程序坞图标本身就是状态显示与唯一入口**（左键回页面 / 右键出菜单），服务未运行时左键直接拉起服务；图标实时区分 `关闭 / 空闲 / 进行中 / 待关注` 四态；任务完成由**真实的 goal 结束事件**驱动，并在图标上累加完成数。

## 使用

1. 把 `DeepSeek Harness 开关.app` 拖进「应用程序」，双击打开（或拖到程序坞固定）。
2. App 启动时**如实显示服务状态**（未运行则显示红色「关闭」），**不会自动拉起 dsh**。
3. **左键**点程序坞图标 = 启动服务并打开 dsh 页面（已运行则回到页面）。
4. **右键**点程序坞图标 = 打开操作菜单（停止服务需二次确认）。
5. 菜单栏小图标点击可打开同一套菜单。

> 提示：首次使用请允许系统通知权限，才能收到「需要确认 / 任务完成」通知。

## 可选增强：dock-bridge 宿主插件

本仓库还附带一个小巧的 dsh 宿主插件 `plugins/dsh-dock-bridge`。装上它之后，App 不必再去解析 dsh 的启动日志，而是由 dsh 进程**直接把端口、PID 和带 token 的地址写出来**：

```sh
# 从本地路径安装（把路径换成你的克隆位置）
dsh plugin --profile web add /path/to/dsh-dock-launcher/plugins/dsh-dock-bridge
```

装完重启一次 web profile 即可。要点：

- 插件写 `~/.config/dsh-dock-launcher/runtime.json`（权限 `0600`，因为里面是活的 token），进程退出时删除；SIGTERM 退出路径也覆盖。
- App 只在「上报 PID 仍存活」且「端口仍可连」时才采信该文件，崩溃残留会被自动忽略并回退读日志。
- **不装插件也完全可用**：回退路径就是从 `~/Library/Logs/dsh-web.log` 里解析带 token 的地址。
- 右键菜单「环境自检…」会显示当前走的是哪条路径。

> 该插件同时是本仓库向 [awesome-dsh-plugin](https://github.com/awesome-dsh-plugin/awesome-dsh-plugin) 的投稿条目（它需要一个可 `dsh plugin add` 安装的宿主插件，而不是纯 `.app`）。

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
├── plugins/dsh-dock-bridge/    # 可选宿主插件：提供端口/PID/带 token 地址（可 dsh plugin add）
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
