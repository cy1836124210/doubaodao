# 豆包桌面端 (v2.30.4) 接口逆向文档

> 逆向方式：CDP (`--remote-debugging-port=9222`) attach 到 `doubao://doubao-chat/chat` 页面，
> 注入 `tools/hook.js`（fetch/XHR/WebSocket/EventSource 包装 + `Runtime.addBinding` 回传），
> 配合 `Network.getRequestPostData` 抓请求体；静态部分来自 `local_webcontents` JS 与 `biz.pak` 生成客户端。
> 全部抓包数据在 `E:\doubaoni\capture\hook.jsonl`（17k+ 条），工具在 `E:\doubaoni\tools\`。

## 0. 通用约定

所有 `www.doubao.com` 业务请求：

- **Query 公共参数**（每个 URL 都带）：
  `version_code=20800&language=zh&device_platform=web&doubao_device_platform=desktop&aid=582478&real_aid=582478&pkg_type=release_version&device_id=<dev>&pc_version=2.30.4&doubao_pc_version=2.30.4&web_id=<webid>&tea_uuid=<dev>&region=CN&sys_region=CN&samantha_web=1&web_platform=desktop&use-olympus-account=1&runtime=web&runtime_version=3.37.9&client_platform=pc_client&chromium_version=147.0.7727.149&channel=win&fp=verify_<dev>&web_tab_id=<uuid>`
- **必带 Header**：`Agw-Js-Conv: str`（少了会报 `712012002`）
- **Content-Type 陷阱**：`/im/*` 用 `application/json; encoding=utf-8`（注意是 `encoding=` 不是 `charset=`；写错同样 `712012002`）。`/samantha/*` 用普通 `application/json` 也可以。
- **Cookie 鉴权**：会话 Cookie（`sessionid` 等），页面内 `credentials:'include'` 自动带。
- `/chat/completion`、`/chat/async/chunk_stream` 还可能有 `msToken`、`a_bogus` 签名参数（风控按需出现）。
- 响应统一包 `{code, msg, data}`（samantha）或 cmd 信封（/im）。

## 1. 会话（当前会话 / 会话列表 / 历史消息）—— IM cmd 信封协议

`POST https://www.doubao.com/im/<path>?<公共参数>`，body 为统一信封：

```json
{"cmd": <数字>, "uplink_body": {"<xxx_uplink_body>": {...}},
 "sequence_id": "<uuid>", "channel": 2, "version": "1"}
```

响应：`{"cmd": <同>, "sequence_id": "<同>", "downlink_body": {"<xxx_downlink_body>": {...}}, "status_code": 0, "status_desc": "OK"}`

| 接口 | cmd | uplink_body 键 | 用途 |
|---|---|---|---|
| `/im/conversation/info` | 1110 | `get_conv_info_uplink_body{conversation_id, conversation_type:3, ext:{cold_start}, option:{need_bot_info:true}}` | **当前会话详情**（名称、头像、bot_id、participant 等） |
| `/im/conversation/batch_get` | 1111 | `batch_get_conv_info_uplink_body{conversation_id:[...], option:{recent_message_count_per_conv:1}}` | 批量会话信息 |
| `/im/conversation/modify` | 1114 | `modify_conversation_uplink_body{conversation_id, mode_id, model_item_key, reasoning_effort}` | 改模型/思考强度等 |
| `/im/conversation/abstract` | 3500 | `pull_conversation_abstract_uplink_body{conversation_id, scene_param{limit,scene}}` | 会话摘要/各场景消息计数（打开会话时调用） |
| `/im/chain/single` | 3100 | `pull_singe_chain_uplink_body{conversation_id, anchor_index, direction, limit:20, filter{index_list}}` | **拉历史消息链**（单会话分页，`index_in_conv` 游标） |
| `/im/chain/thread_message` | 3102 | `pull_thread_message_chain_uplink_body{thread_id, limit:20, direction:3, anchor_index}` | **子代理线程消息链**（计划/进度内容就在这里） |
| `/im/thread/info` | 3400 | `get_thread_info_uplink_body{thread_id}` | **线程状态**：`thread_info.ext.thread_status` = `running`/`completed`，`thread_name` 为任务名 |
| `/im/chain/recent_conv` | 3200 | `pull_recent_conv_chain_uplink_body{limit:20, message_count_per_conv:10, option{...}}` | 侧边栏最近会话列表 |
| `/im/message/mark_conv_read` | 2100 | `mark_conv_read_uplink_body{conversation_id}` | 标记已读 |
| `/im/message/chain_by_block` | 3501 | `pull_message_chain_by_block_uplink_body{block_type_list:[...], limit:30}` | 按 block_type 拉消息（附件/产物等） |
| `/im/project/list` | 4605 | `list_projects_uplink_body{limit, sort_type}` | 项目列表 |
| `/im/group/list` | 4607 | `list_conversation_groups_uplink_body{group_by:1, limit:20}` | 会话分组 |
| `/im/message/send_rate_limit` | 2260 | `check_message_send_rate_limit_uplink_body{}` | 发送限流检查 |

消息对象核心字段：`message_id`、`sender_id`（用户=user_id，AI=bot_id `7338286299411103781`）、`content_block[]`（每个含 `block_type/block_id/content`）、`ext`（`chat_id`、`bot_id`、`agent_mode` 等）。

## 2. 流式回复接口 —— `POST /chat/completion`

`POST https://www.doubao.com/chat/completion?<公共参数>`，SSE 流。

请求体顶层：`{client_meta, messages, option, user_context, ext}`

```jsonc
{
 "client_meta": {"conversation_id": "3844...", "bot_id": "7338286299411103781",
                 "last_section_id": "...", "last_message_index": 5, "local_permissions":[...]},
 "messages": [{"local_message_id": "<uuid>", "message_status": 0,
               "content_block": [{"block_type": 10000,
                 "content": {"text_block": {"text": "用户输入"}},
                 "block_id": "<uuid>"}]}],
 "option": {"create_time_ms": ..., "agent_mode": 2, "need_deep_think": 0,
            "is_regen": false, "unique_key": "<uuid>", "support_lazy_fetch_stream": true,
            "sse_recv_event_options": {"support_chunk_delta": true},
            "model_config": {"model_item_key": "0", "reasoning_effort": 3},
            "general_task_param": {...}, "aggregate_params": {...}},
 "user_context": {...}, "ext": {...}
}
```

SSE 事件（`event:` + `data:{seq_no, event_id, ...}`）：

| event | 含义 |
|---|---|
| `SSE_HEARTBEAT` | 心跳 |
| `SSE_ACK` | 确认，分配 conversation_id/message_id/section_id（内部事件 ACK） |
| `FULL_MSG_NOTIFY` | 全量消息通知 |
| `STREAM_MSG_NOTIFY` | 流式消息通知 |
| `STREAM_CHUNK` | 内容块增量，`data.patch_op[]` = `{patch_object, patch_type, patch_value}`；patch_object: 1=消息级, 3=block 级, 50=ext 级, 111=?；patch_type 1=写值 2=追加文本 |
| `CHUNK_DELTA` | 轻量增量（`support_chunk_delta` 开启时） |
| `STREAM_TIMEOUT_CONTROL` | 超时控制 |
| `ASYNC_CHUNK_SNAPSHOT` | 异步快照（恢复用） |
| `SSE_REPLY_END` | 本条回复结束（FIN） |

**block_type 字典**（`content_block[].block_type`）：
`10000` 文本 `10006` 网页读取(link_reader) `10019` 文件操作 `10024` 通用工具(TodoWrite 等) `10025` 搜索结果 `10040` 思考(thinking_block) `10052` 附件 `10063` 本地文件产物 `10091` 耗时 `10059` super_task PPT 模板 `2074/10020/10021/10030` 其他。

**异步任务移交**：当回复转为后台超能任务时，STREAM_CHUNK 里出现
`fin_reason: {reason: FinReasonAsyncTask, async_task: {id: <task_id>}}`，
前端拿到该 `task_id` 后开第二条流（见 §4）。

## 3. 计划/进度接口 —— MoA 多智能体（Plan 进度）

「计划进度」由三层组成：

1. **主回复流里的 `complex_task_block`**（`/chat/completion` 或 `/im/chain/single` 消息内）：
   ```jsonc
   {"block_type": <复杂任务块>, "content": {"complex_task_block": {
      "thread_id": "5635...",           // 子代理线程 id
      "display_type": "organizer" | "sub_agent",
      "agent_type": "organizer" | "supertask",
      "header": {"summary": "已开始工作/已完成工作", "name": "任务名", "icon_url": ...},
      "title": "任务标题",
      "status": 2 /*已完成*/ | 4 /*组织者*/ ...
   }}}
   ```
2. **`POST /im/thread/info`（cmd 3400）**：轮询每个 `thread_id` 得到
   `thread_info.ext.thread_status` = `running` → `completed`（实测状态会翻转）。
3. **`POST /im/chain/thread_message`（cmd 3102）**：拉线程内消息（thinking 块、工具调用块等即“计划执行明细”）。

实测线程：organizer `56356036522376194`（"2026新能源车行业报告"）+ 5 个 supertask 子代理（市场规模调研/竞争格局/供应链/飞书文档/HTML 可视化）。

## 4. 子代理/异步任务流式接口 —— `POST /chat/async/chunk_stream`

子代理（或恢复中的异步任务）的实时内容流，SSE，可断线续传。

请求体（实测抓包）：
```json
{"task_id": "56544991295959554",      // = 该回复消息 message_id（不是 thread_id）
 "seq_start": 0,                     // 续传：已收到的最大 event seq
 "append_scene": 6,                  // 6=sub-agent, 7=organizer（dy.SubAgent/ThreadOrganizer 枚举）
 "need_snapshot": true,
 "support_lazy_fetch_stream": true,
 "ext": {}}
```
代码中构造：`{asyncTask: {task_id, seq_start:0, append_scene, need_snapshot, support_lazy_fetch_stream, ext:{}}}`

事件含 `ASYNC_CHUNK_SNAPSHOT`（全量快照）+ `CHUNK_DELTA`/`STREAM_CHUNK` 增量；每个事件带 `event_id`，重连时作为 `seq_start` 传回跳过已收事件。

另有一条 **`POST /samantha/chat/async/stream`**：超能任务（单任务模式）恢复流，
body = `{task_id, event_id: <lastEventId>, ...sentEvent}`，事件类型 `BLOCKLIST / ERR / FIN / VERBOSE`。

## 5. 任务结束接口

前端停止流程（`async-skill-message-lifecycle.js` / `async-skill-content-block.js` 中解码）：

```js
const taskId = message.async_task?.id;   // 来自 fin_reason.async_task.id
await SamanthaChat.cancelAsyncTask(taskId);   // 1) mojom 原生桥，掐断本地流
await TerminateSuperTask({task_id: taskId});  // 2) HTTP 终止
```

- **`POST /samantha/supertask/terminate`** — body `{"task_id": "<id>"}`。
  实测 App 在会话销毁时对每个已知任务 id（thread_id 和 chunk_stream 用的 message_id 都发）逐个调用，全部 `HTTP 200`。
  对已完成的任务重复调用返回 `{"code":710022001,"msg":"系统错误"}`（幂等性不保证，终止中的任务返回 code:0）。
- **`POST /samantha/supertask/reactivate`** — body `{"task_id": "<id>"}`，重启任务（超能模式 agent）。
- **`POST /samantha/code/interrupt_async_ask`** — body `{"section_id","message_id","conversation_id"}`，中断异步代码问答任务。
- **`POST /samantha/supertask/apply`** — 开启超能模式（无 body）；`GET /samantha/supertask/setting`、`GET /samantha/supertask/recommend`、`GET /samantha/supertask/moa_switch_pop_up` 等配套。

## 6. 推送通道

`wss://wss100-normal.doubao.com/ws/v2` —— 长连接推送（应用层心跳文本帧 `hi`），
用于跨端同步/新消息通知；抓包只见到心跳，业务帧为二进制 protobuf（hook 中显示为 `B64:`）。

## 7. 其他实用接口（节选，完整 352 条见 `api_endpoints_full.txt`）

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/samantha/conversation/list` | 会话列表（samantha 侧） |
| POST | `/samantha/user/setting/get` | 用户设置+AB 配置 |
| POST | `/samantha/skill/list` `/samantha/skill/recommend` | 技能列表/推荐 |
| POST | `/samantha/tool_message/put_chat_record` | 工具消息回写 |
| GET  | `/samantha/notice/info` | 通知未读数 |
| POST | `/samantha/plugin/prompt_skill/list_by_user` | 用户提示词技能 |
| POST | `/alice/user/config/pull` | 用户配置 |
| POST | `/alice/resource/prepare_upload` | 上传准备（返回 tos 上传地址） |
| GET  | `/samantha/meeting/summary/status?task_id=` | 会议纪要任务状态 |
| GET  | `/alice/resource/watermark_task?task_id=` | 水印任务轮询 |

监控/埋点（非业务）：`mcs.doubao.com/list`（事件埋点）、`opt.doubao.com/monitor_browser/collect/batch/`（Slardar 性能）、`mon.zijieapi.com`（语音 SDK 遥测）。

## 8. 复现工具

| 文件 | 用途 |
|---|---|
| `tools/hook_daemon.py` + `tools/hook.js` | 流量录制守护进程（自动 attach 所有 target）→ `capture/hook.jsonl` |
| `tools/cdp.py` | CDP WebSocket 客户端（`suppress_origin=True`） |
| `tools/send_chat.py` + `press_enter.py` | 页面内输入并发送消息 |
| `tools/capture_post.py` | `Network.getRequestPostData` 抓 POST 体 |
| `tools/test_terminate.py` | 页面内直接调 `supertask/terminate` 验证 |
| `tools/poll_threads2.py` | 页面内轮询 `/im/thread/info` |
| `tools/extract_api.py` | 从 biz.pak 提取 352 个生成端点 → `api_endpoints_full.txt` |
| `tools/decode_streams.py` | 解码 hook.jsonl 中 base64 流块 |
| `tools/dump_im.py` / `dump_terminate.py` / `dump_chunkreq.py` | 按端点回放抓包样本 |

启动方式：豆包以 `--remote-debugging-port=9222` 启动后跑 `python -u tools/hook_daemon.py`。
