# IslandBridge — 豆包 → 星河岛 局域网桥

把豆包的 AI 回复/计划任务实时推到手机星河岛。**v2 起网络层走 HTTP SSE**（与星岛通道同构），并内置 LSPosed 模块可直接抓手机豆包 App。

- **plan 进度 → 下载样式**：`PROGRESS` 模板 + 进度环，按子任务完成数显示 `done/total`
- **任务开始/结束 → 岛展开/缩回**：开始自动展开，结束 outro（绿勾✓ + 一句话，1.6s 收）
- **推流文本 → 歌词样式**：`MEDIA` 模板 `lyricsLine`，思考/工具状态在胶囊里滚动
- **回复接口**：`chat.reply` 全量文本只进 App 内仿豆包回复页，**暂不上岛**（协议已预留）

## 结构

```
pc/        电脑端（Python）：CDP 抓豆包桌面端 → 归一化 → SSE 广播
android/   手机端（Kotlin）：岛 SDK 投送 + SSE 订阅 + WebView 回复页 + LSPosed 模块
```

## 电脑端

### 安装方式 A：exe 安装程序（推荐，与豆包共生）

`pc/installer/build.bat` 产出两个 exe（PyInstaller，无外部依赖）：

- `dist/IslandBridgeSetup.exe` —— 安装器（console）。自动定位豆包 → 释放 daemon 到 `%LOCALAPPDATA%\IslandBridge\` → **把 `--remote-debugging-port=9222` 注入豆包所有启动入口**（`HKCU\...\Run` 里的 `doubao` 自启项 + 桌面/开始菜单/固定任务栏快捷方式）→ 注册 `IslandBridgeDaemon` 开机自启并立即拉起。`--uninstall` 完整回滚。
- `dist/IslandBridgeDaemon.exe` —— 无窗后台 daemon。命名互斥锁保证单实例；日志写 `daemon.log`（exe 同目录）；CDP 断线自动重连重插桩；每 5min 守护线程复查启动入口（豆包更新重建快捷方式后自动补回 flag），若发现运行中的豆包没带 flag 会在日志里告警。

共生原理：不注入、不改豆包文件，只在启动参数上加调试端口。豆包 stub（`Doubao\Doubao.exe`）会把参数透传给 `app\Doubao.exe`（已实测验证）。

### 安装方式 B：手动跑 Python（开发用）

```bash
# 1. 以调试端口启动豆包（或用 pc/start_doubao_debug.cmd）
Doubao.exe --remote-debugging-port=9222

# 2. 启动桥（依赖 ../tools/cdp.py 和 ../pylibs/websocket-client）
python pc/bridge_daemon.py            # 默认 HTTP 端口 8787
python pc/bridge_daemon.py --port 9000 --log events.jsonl
```

`pc/config.json`（冻结版读 exe 同目录）可改 `port` / `cdp_port` / `log`。

### 电脑端监控

- **浏览器监视页**：打开 `http://localhost:8787/`（或 `http://<电脑IP>:8787/`）—— 实时滚动显示所有事件、连接状态、订阅客户端数
- **CLI 监控**：`python pc/monitor.py` —— 时间戳 + 着色的精简事件流（`♫ think/text` 歌词增量、`plan.*` 进度）
- **接口**：`GET /health` → `{"ok":true,"clients":N}`；`GET /events` → SSE 订阅
- **落盘日志**：`--log events.jsonl` 时每条事件追加一行，`tail -f pc/events.jsonl`

## 手机端

前提：手机已装星河岛 1.1（或带 `HOST_PROTOCOL` 的星流）。

```bash
cd android
./gradlew :app:assembleDebug     # 产出 app/build/outputs/apk/debug/app-debug.apk
```

安装后打开 App：填电脑局域网 IP + 端口 → 「连接」。「测试进度」「测试歌词」「结束测试」可不发消息直接验证岛上效果。

### LSPosed 模块（同一个 APK）

APK 同时是 LSPosed 模块（`assets/xposed_init` + `xposedmodule` meta-data）。在 LSPosed 管理器里启用「豆包岛桥」，勾选作用域：

| 作用域 | 作用 |
|---|---|
| `com.larus.nova`（豆包） | 按 `D:\aiwork\apk\REVERSE_NOTES.md` hook `OmniHttpCallByNative.writeMetaInfo/writeChunkData`，进程内解析 SSE → `BridgeEventReceiver` → 岛；并对 3 个 `Omni*Dispatcher` 打日志便于细化字段；每 60s 保活 ping |
| `android`（system_server） | 每 5min 显式广播唤醒 `KeepAliveReceiver` → 拉起 `BridgeService` 前台服务，保活 SSE 连接 |

手机端事件与电脑端走**同一事件协议**（`pc/protocol.md`），两条来源可同时工作：电脑推豆包桌面端，模块抓豆包 Android 端。

### 保活链

`BridgeService`（前台服务 dataSync）持有 SSE 连接；唤醒来源：开机 `BootReceiver`、LSPosed 保活广播、App 内「连接」。

## 事件 → 岛 映射

| 事件 | 岛内容项 | 模板 |
|---|---|---|
| `plan.start` | id=`plan`，`LIVE_UPDATE`，DOWNLOAD 图标 + 进度环，`alertOnStart` | PROGRESS |
| `plan.progress` | 整份替换 `plan`，ring=fraction，subtitle=当前子任务 | PROGRESS |
| `plan.end` | `end(plan, outro)` | 收尾勾叉 |
| `chat.start` | id=`reply`，`MESSAGE`，豆包头像 + 标题「手机/电脑-会话名」+ `postedAtWallMs` | MESSAGE |
| `chat.delta`(text/think) | 正文 body 流式更新 + 胶囊信息区滚动（300ms 节流） | MESSAGE body |
| `chat.end` | 最后一次更新卡片（不主动 `end`，留岛等操作/超时） | — |
| `chat.reply` | **不上岛** → App 回复页 | — |

回复卡生命周期（接入库 1.3.0 / 宿主协议 v6）：`reply=true` 回复输入条 → `island.onReply`；
操作（点卡片空白处=开豆包 / 停止会话 / 删除会话 / 发送回复）→ 立即 `end`；
无操作则 `dismissAfterMs=60s` 后宿主 `onExpired` 自动撤下。
`hideWhenSourceForeground=false`（默认 true，本 App 前台会退副岛）。

协议细节见 `pc/protocol.md`。岛上限：文本总 8KB、歌词行 512 字、同屏 3 项、10 次/秒（已按协议节流）。

## 排错

- LSPosed 日志里搜 `IslandBridge`：应看到 `hooked writeChunkData(...)` / `nova ctx captured` / `system pinger armed`；`dsp Omni*Dispatcher.xxx(...)` 行显示各分发器实参类型，用于后续细化字段。
- 手机抓不到事件：确认作用域勾选后**强行停止并重启豆包**；system_server 作用域改动需重启手机。
- 豆包版本升级可能改类/方法名 → 对照 `apk/REVERSE_NOTES.md` 更新 `DoubaoHookEntry` 里的类名。
