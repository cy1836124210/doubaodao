# IslandBridge 局域网协议（v2 — SSE）

手机 App 订阅 `http://<电脑IP>:<port>/events`（默认端口 8787，可在 `config.json` 改），
`Accept: text/event-stream`，与星岛通道同构。每条 `data:` 帧是一个 JSON，字段 `t` 为类型；
`:` 开头为心跳注释行，每 15s 一条。`GET /health` 返回 `{"ok":true,"proto":"islandbridge-sse/1","clients":N}`。

事件帧也可由 LSPosed 模块在手机本地产生：模块在 com.larus.nova 进程内抓
`OmniHttpCallByNative.writeChunkData` 的 SSE 字节，用同一套事件协议
`sendBroadcast` 给 `com.islandbridge/.BridgeEventReceiver`（extra `v`=1, `ev`=json）。

## 回复发送（上行）

| 方向 | 通道 | 说明 |
|---|---|---|
| 手机→PC豆包 | `POST /reply`，body `{"text":"...", "cid":"..."}` → `{"ok":bool,"detail":...}` | **首选**:页面内重放已捕获的 `/chat/completion` 模板(island_hook.js `__ibSendReply`:克隆 body→换 cid/text/新 uuid→经 `window.fetch` 重发,签名层自动补 msToken/a_bogus,cookie 自动带);模板按 cid 存 `send_templates.json` 并在注入时回填。**兜底**:CDP `Input.insertText`+回车注入 |
| 手机→手机豆包 | 广播 `com.islandbridge.SEND` (`setPackage("com.larus.nova")`, extras `text`,`cid`) | 模块在豆包进程内反射调用 `OmniMessageService.sendMessageV2` |
| 停止生成 | 广播 `com.islandbridge.STOP` (extras `cid`) | 模块重放 `interruptMessage` |
| 回执 | 事件 `{"t":"send.result","ok":bool,"err":...,"act":...}` 走正常事件通道回来 | 失败时 App 端回退剪贴板+拉起豆包 |

## 事件类型

| t | 含义 | 主要字段 | 手机端动作 |
|---|---|---|---|
| `chat.start` | 新回复开始 | `mid` 消息id | 上岛：MEDIA 歌词项（icon MESSAGE + waveform） |
| `chat.delta` | 内容增量 | `mid`, `kind`, `text` | `kind=think/tool` → 歌词行滚动；`kind=text` → 回复页追加 |
| `chat.end` | 回复流结束 | `mid` | 歌词项 `end` + outro |
| `chat.reply` | 回复全量文本 | `mid`, `text` | **不上岛**，推给回复页渲染 |
| `chat.async` | 转后台异步任务 | `mid`, `task_id` | 歌词行提示"已转后台任务" |
| `chat.conv` | 会话标题揭晓 | `cid`, `cname` | 更新岛 MEDIA 标题 / 回复页会话名 |
| `plan.start` | 计划任务开始 | `tid`, `title` | 上岛：LIVE_UPDATE + PROGRESS（下载样式，ring=0） |
| `plan.progress` | 计划进度 | `done`, `total`, `name` | 更新 ring 与进度条，`name`=当前子任务 |
| `plan.end` | 计划全部完成 | `success`, `text` | `end` + outro（绿勾/红叉） |
| `ping` | 心跳 | — | 忽略 |

所有 `chat.*` 事件可能带 `cid`（会话 id，`STREAM_MSG_NOTIFY.meta.conversation_id`）
和 `cname`（会话标题，从 `/im/conversation/info` 的 `conversation_info.name` 学得；
标题晚到时由 `chat.conv` 事件补发）。用于区分消息属于哪个对话。

## 节流约定

`chat.delta` 可能很密；手机端对歌词更新按 ~300ms 合并（岛侧 250ms 内只上屏最后一次，全源 10 次/秒上限）。

## 字段上限（岛侧）

歌词行 ≤512 字、标题 ≤128、副标题 ≤256；超长按岛规则截断。
