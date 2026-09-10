# DeepSeek Harness 开关（常驻状态型程序坞应用）

一个运行在 macOS（Apple Silicon / M4）上的**常驻**小程序：程序坞图标 = **拨动开关**，
点击在「启动 / 停止 DeepSeek Harness」之间切换；菜单栏小图标实时显示任务状态，
当任务**需要确认**或**完成**时做不同的动态效果提示。

## 成品

```
DeepSeek Harness 开关.app   （当前版本 v0.4.2）
```

## 功能

- **双向开关**：Dock 图标点击切换 启动 / 停止 `dsh web`；图标实时变脸：
  - `ON`（绿色，滑块在右）= 服务运行中
  - `OFF`（红色，滑块在左）= 服务已停止
  - `蓝` = 任务进行中　`橙` = 需要确认　`绿`= 任务完成（短暂）
- **停止二次确认**：服务运行中点击 Dock 图标或菜单「停止服务」会先弹出确认框（停止 / 取消），防止误关闭；确认后图标立即拨向红色关闭态。
- **常驻**：无窗口、挂在 Dock + 菜单栏；菜单栏小图标用颜色表示当前状态。
- **动态效果提示**（当任务需要确认 / 完成时）：
  - **需要确认** → 橙色图标 + Dock 持续弹跳（`critical`）+ 系统通知 + 徽标 `!` + 提示音 `Purr`
  - **任务完成**（真正的 goal 结束）→ 一次弹跳（`informational`）+ 系统通知 + 徽标 `✓` + 成功音 `Glass`
  - 启停音效：服务就绪 `Pop`、服务停止 `Funk`
- **任务状态监测**：读取 `~/.dsh/sessions/*/session.jsonl.zstd` 最新活跃会话日志：
  - `approval/request`、`approval/asked` → **需要确认**
  - `turn/end`（普通对话回合结束）→ **任务完成**；存在活跃 goal 时回合结束不打扰，改为 `goal/change`（`operation == "complete"` / `goal.phase == "complete"`）→ **任务完成**
  - `turn/start` → **进行中**

> 完成提示规则：会话没有活跃 goal 时，一轮对话结束（`turn/end`）即算完成；会话存在活跃 goal 时，只在整个 goal 真正结束（`goal/change · complete`）时提示。监测覆盖所有近期活跃会话，多会话并行不漏检。

## 使用

1. 把 `DeepSeek Harness 开关.app` 拖进「应用程序」。
2. 双击打开（或拖到程序坞固定）。**首次启动会自动把服务拨到 ON**（若尚未运行）。
3. 之后点程序坞图标 = 点击开关：运行中→停止；停止→启动。
4. 菜单栏小图标右键打开菜单：启动/停止服务、打开浏览器、打开日志、版本、退出。

> 提示：首次使用允许系统通知权限，才能收到「需要确认 / 任务完成」通知。

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
./build.sh          # 一键：绘图标→打包 icns→编译→组装→签名，并自动注入版本号
```

- 改图标颜色/造型：`src/Icons.swift`；改应用图标：`src/draw_icon.swift`。
- 改启动/监测/提示逻辑：`src/ServiceManager.swift`、`src/TaskMonitor.swift`、`src/main.swift`。

## 目录结构

```
dsh-dock-launcher/
├── src/
│   ├── main.swift          # 常驻应用：Dock/菜单栏、定时监测、动画+通知、点击切换启停
│   ├── ServiceManager.swift# 启动/停止/端口探测
│   ├── TaskMonitor.swift   # 定位会话日志、zstd 解压、事件识别
│   ├── Icons.swift         # ON/OFF/运行/确认/完成 开关图标 + 菜单栏小图标
│   └── draw_icon.swift     # 用 CoreGraphics 绘制 App 图标(生成 1024px PNG)
├── Info.plist              # 应用元数据
├── build.sh                # 一键构建脚本（读取 VERSION/BUILD_NO 注入版本号）
├── VERSION                 # 语义版本号（第一行）
├── BUILD_NO                # 构建号（每次构建自增，已 gitignore）
├── CHANGELOG.md            # 版本记录
├── DeepSeek Harness 开关.app   # 成品
└── README.md               # 本说明
```
