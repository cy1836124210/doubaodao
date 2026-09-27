# 岛动作（删除 / 停止）修复适配报告 — 最终版

> 依据：`D:\aiwork\apk\classes24.dex` 反汇编 `d24.txt`（UTF-16LE，3 426 714 行）
> + 真机 d666858b（OP5D0DL1 / Android 16）实测 logcat。
>
> **最终结论（2026-09-27）**
> 1. **停止功能已整体删除。** 豆包本身没有「停止」按钮，这个动作在原 App 里不可达，
>    属于我们凭空发明的功能，已连同 `MessageSender` 里整套 interrupt 机器一起移除。
> 2. **删除功能已真机验证可删。** 但原实现有个残留 bug：`island.end()` 在会话
>    尚未绑定时发出，返回 `rc=9` 被静默丢弃 → 岛里留着旧卡片。已修并实测。
> 3. 修复过程中又抓到两个隐藏 bug（自我投毒 / 心跳来源混淆），一并修掉。

---

## 0. 一句话总结

| 动作 | 结论 |
|---|---|
| **停止** | **删除**。豆包 UI 无此能力，真机 12 次 UI dump 无「停止」节点；即使强行调 `interruptMessage`，`iim` 回调也是 `code=-1` 失败。 |
| **删除** | **可用**。真身是 `NativeConversationServiceImpl.deleteConversation`（不是那个空壳 `ConversationServiceImpl`）。 |
| **删除残留** | **根因找到并修复**：`island.end()` 早于 session 绑定，`rc=9` 丢失。 |

---

## 1. 停止（STOP）—— 为什么是「删除」而不是「修复」

### 1.1 用户的事实纠正

用户明确指出：**豆包本来就没有停止的功能**。这不是我们的调用姿势不对，
而是「停止一次正在进行的回复」在豆包产品里根本不是一个可发起的操作。

### 1.2 真机证据（三重印证）

**(a) UI 层**：流式回答进行中连续 poll `uiautomator dump` 12 次，
**没有任何 `停止` / `中断` 节点**。

**(b) 调用层**：`OmniMessageService.interruptMessage` 即使被反射调进去
（`tryInterrupt ok (high)` 只说明反射 invoke 没抛异常），异步回调仍然是：

```
iim fail IMError(code=-1, tips=null, exception=null, ext=null)
```

**(c) 行为层**（marker-split 实验，最硬的证据）：
先 `log -t IB_MARK "STOP_FIRED_NOW"` 打标记，再按行号切分 logcat 统计增量：

```
chat.delta  BEFORE stop = 34
chat.delta  AFTER  stop = 255      ← 完全没停
```

结论：`OmniBreakReason_CLICK_BREAK_BUTTON` 从 UI 侧不可达，整条停止链路是死代码。

### 1.3 移除清单

**`IslandBridge.kt`**
- 删 `const val ACT_STOP = "stop"`、`const val BCAST_STOP = "com.islandbridge.STOP"`
- 删 `onAction` 里的 `ACT_STOP -> { … }` 分支（`ACT_DELETE ->` 直接接 `ACT_OPEN_DOUBAO`）
- 删 `private var replyMid` 及两处学习点（`o.optString("mid")…`、`chat.start` 里那行）
- 删 `onSendResult` 里的 `BCAST_STOP -> { dismissReply("已停止"); return }`
- 流式卡片按钮只剩 `[删除会话]`；结束态只剩 `[我知道了]`
- 类注释改为 `- 按钮  回复 / 删除会话`

**`DoubaoHookEntry.kt`**
- 删 `const val ACT_STOP`，IntentFilter 只剩 `ACT_SEND` + `ACT_DELETE`
- 删 dispatch `when` 里的 `ACT_STOP -> MessageSender.interrupt(cid, mid)`
- 删 `mid` 局部变量两处（随 `MessageSender.lastMid` 一起）

**`MessageSender.kt`**
- 删字段 `intrMethod` / `intrThis` / `intrArgs` / `omniSvc` / `breakReasonCls` /
  `omniSvcCls` / `lastMid`
- 删函数 `interrupt()` / `interruptHigh()` / `interruptNative()` /
  `liveMessageService()` / `resolveMessage()` / `synthMessageService()` /
  `restoreIds()`
- 删 `const val BREAK_REASON_CLS`
- **保留** `idFile` / `persistIds()`（仍被两个铸 id 点调用）
- **保留** `OmniMessageService.interruptMessage` 上的 hook，但降级为
  **纯诊断**：只打日志 `"interrupt args: …"`，注释写明豆包无此按钮、无功能依赖

---

## 2. 删除（DELETE）—— 能删，但岛里会留卡片

### 2.1 DEX 里的大坑（修正了早期误判）

| 类 | 方法 | dex 偏移 | 实质 |
|---|---|---|---|
| `ConversationServiceImpl` | `deleteConversation` | — | **11 code units 空壳**（`checkNotNullParameter` ×2 + `return-void`） |
| `NativeConversationServiceImpl` | `deleteConversation` | — | **真身，74 code units**，走 `Companion.get()` |
| `MessageServiceImpl` | `sendMessageV2` | `494574` | 空壳，且 **dex 内零调用点** |
| `MessageServiceImpl` | `getLatestMessage` | `494118` | 空壳 |
| `NativeMessageServiceImpl` | `v(MessageRequestV2, IIMCallback)` | `5d8ca8` | **真·发送** |

真实删除路径（已真机验证，会话确实从列表消失）：

```
NativeConversationServiceImpl.Companion.get()
  .deleteConversation(cid, DeleteMode_RealDelete, botId, cb)
→ OmniDeleteConversationRequest(cid, CONVERSATION_TYPE_UNKNOWN, modeVal, botId)
→ iim ok true
```

> ⚠️ 千万不要调 `ConversationServiceImpl.deleteConversation` 或 core
> `MessageServiceImpl` 的同名方法 —— 它们是 no-op，会「成功」但什么都没发生。

### 2.2 岛里残留内容的根因（本次真正的修复点）

反编译 `libs/astraisland-client.aar` 里的 `IslandClient.send()` 字节码：

```
session == null  →  bipush 9        // rc=9 = 没有 Binder session，调用没离开进程
session.call 返回 7 且 bind() 失败 →  9
```

翻历史 logcat：**`岛 end(reply) rc=9` 出现了 11 次，11 次全败**。
而旧 `dismissReply()` 不管 `rc` 是不是 0，都照清 `replyShown` / `liveIds`：
**账面以为撤掉了，岛其实还挂着那张卡**，一直显示到宿主的 60s 到期。

时序（`g1.txt` 原文）完美对上：

```
IslandBridge: 已发送到手机豆包
IslandBridge: 岛 end(reply) rc=9          ← 此刻无 session，end 永久丢失
LSPosed:      session offered to com.islandbridge / source bound
IslandBridge: 岛已就绪                    ← 晚了一步
```

**修法**：新增 `pendingEnds: HashSet<String>` 与统一的 `endItem()`：

- `island.isReady == false` → 先把 id 存进 `pendingEnds`（并清掉可能已暂存的 start），
  然后照样尝试 `end`，日志 `岛未就绪(WAITING)，暂存 end(reply)`
- `end` 返回 `rc != 0` → 同样入队重试，日志 `岛 end($id) rc=$rc，已排队重试`
- `flushPendingEnds()` 在 `resync()` 里 `flushPending()` 之后调用，把排队的 end 补发，
  成功记 `岛 end($id) 补发成功`，仍失败记 `岛 end($id) 重试仍失败 rc=$rc` 并再次入队
- `island.start` 的两条成功路径都 `pendingEnds.remove(id)`，
  防止迟到的补发把刚建起来的卡片又收掉
- 所有 `island.end()` 调用点统一改走 `endItem()`（含 `plan.end`）

**修复后实测**：

```
岛未就绪(WAITING)，暂存 end(reply)
岛 end(reply) 补发成功          ← 卡片真的被收掉了
```

---

## 3. 顺手抓出的两个隐藏 bug

### 3.1 发送自我投毒（严重）

为了抓发送模板而加的 hook 会 **连我们自己的出站调用一起捕获**。
在没有真人发送过的进程上，第一次 bridge SEND 会落到手搓的 scratch 路径，
服务端拒绝（`message list empty / error_stage=send_validate`），
**而这个被拒的 bean 被当成模板存了下来** —— 之后每次发送都在克隆这个废包，
全部以同样理由失败。**一次坏发送污染了后续所有发送。**

修法：thread-local 的 `selfSend` 标记 + `inline fun asSelfSend{}` 包住三处
自有出站调用（`v(svc,newBean,…)`、`vm.invoke(svc,req,…)`、
`m.invoke(sendThis,*args)`），三个 `captureHook` 开头 `if (selfSend.get()) return`。
用 thread-local 而非普通布尔，是为了不误伤并发在 UI 线程上的真人发送。

**修复后实测**：连续两次发送，日志里不再出现 `REAL bean req`。

### 3.2 心跳来源混淆（会导致「假绿」）

保活 pinger 有**两份**：一份在豆包进程内（证明注入成功），
一份在 system_server（豆包死了也照发）。旧逻辑不区分，
于是**作用域没勾、模块完全没生效也会显示"已生效"**。

修法：`sendTo(... src)` 带上来源，豆包侧 `SRC_DOUBAO`、系统侧 `SRC_SYSTEM`；
`KeepAliveReceiver` 只在 `src == "doubao"` 时调 `EnvCheck.noteModulePing()`。
已实测：手动发 `src=system` 和不带 src 的广播，落盘时间戳均**不变**。

---

## 4. 环境自检 UI（本轮附带需求）

`MainActivity` 新增「运行环境」卡片：**Root / LSPosed / 模块** 三行 + 圆点状态。

- **为什么要 root 才能查**：`/data/adb` 对普通 App 是内核 SELinux 拒绝
  （实测 `run-as com.islandbridge ls /data/adb` → Permission denied），
  所以静态检测统一走一次 `su -c`，把 `id` / `su` 路径 /
  `/data/adb/{ksu,magisk,ap}` / `/data/adb/lspd` / `zygisk_lsposed/module.prop` /
  `pidof lspd` / `grep modules_config.db` / `pidof com.larus.nova` 一次取回，
  用 `__KEY__` 分段解析，6 秒超时强杀（防 root 授权框没人点导致卡死）。
- **最强证据是心跳**：只有豆包进程里的模块会发 `src=doubao` 的 KEEPALIVE，
  所以只要时间戳新鲜，就说明 **LSPosed 确实把模块注入了 com.larus.nova** ——
  这比任何静态文件检查都有说服力（静态检查只能证明"装过 LSPosed"）。
- 心跳落盘（`shared_prefs/envcheck.xml`，记墙钟时间），
  因为冷启动 `elapsedRealtime` 归零，内存值不可信。
- 5 秒结果缓存，避免每次 `onResume` 都 fork 一次 su。

真机实测输出：

```
运行环境                                   正常
● Root 权限      已 root · uid=0 · KernelSU
● LSPosed 框架   LSPosed 已运行 · v2.2.0 (7854) · 已登记本模块
● 模块状态       模块已生效 · 最近心跳 0s 前
```

### 4.1 踩到的坑（值得记下）

`section()` 第一版用 `Regex("^__(\\w+)__$")` 的**捕获组**当 key（存成 `ID`），
调用方却按 `__ID__` 查 → **每个分段都取空** → 明明 root 正常却报
`未 root · su 不可用`。改成存 `m.value`（整行含下划线）后正常。
**UI 自检类代码必须用真机输出回归，不能只看编译通过。**

---

## 5. 顶部沉浸式状态栏

Android 15 起系统强制 edge-to-edge，旧代码内容会钻到状态栏底下。

- `WindowCompat.setDecorFitsSystemWindows(window, false)`
- `statusBarColor` / `navigationBarColor` 透明
- `WindowInsetsControllerCompat.isAppearanceLightStatusBars = false`（深色底 → 浅色图标）
- 根布局挂 `ViewCompat.setOnApplyWindowInsetsListener`，
  把 `systemBars() or displayCutout()` 的 top 留成内边距，
  bottom 取 `max(systemBars.bottom, ime.bottom)` 以便键盘弹出时输入框不被挡

**实测**：状态栏 `InsetsSource frame=[0,0][1440,160]`，
标题节点 `bounds=[0,160][1440,326]` —— 起点正好 160，无重叠；
状态栏区域取色 65% `#101018`，正是 App 自己的深色底，确认是真沉浸而非单独一条栏。

---

## 6. 电脑端连接配置：暂时隐藏

按要求隐藏了「电脑IP / 端口 + 连接 / 断开」。
为了将来一行恢复，没有删代码，而是加开关：

```kotlin
/** 电脑端（SSE）连接配置：暂时不显示。改为 true 即可恢复。 */
private const val SHOW_PC_CONFIG = false
```

`BridgeService.ensureConnected()` 仍会按已保存的 prefs 自动重连，隐藏不影响后台逻辑。

---

## 7. 验证方法（真机）

```bash
ADB=/d/tool/android-sdk/platform-tools/adb.exe

# 装 + 重启豆包让 LSPosed 重新注入
$ADB install -r android/app/build/outputs/apk/debug/app-debug.apk
$ADB shell "su -c 'am force-stop com.larus.nova'"
$ADB shell "monkey -p com.larus.nova -c android.intent.category.LAUNCHER 1"

# 只抓模块与 App 的日志（重定向文件是 UTF-8，读时务必 -Encoding UTF8）
$ADB logcat -v brief IslandBridge:V LSPosedFramework:V '*:S'

# 环境自检：保持 App 在前台，等 ~70s 让豆包侧心跳到达
$ADB shell "am start -n com.islandbridge/.MainActivity"
```

期望看到：

- 模块注入：`IslandBridge nova ctx captured` / `hooked REAL send v(MessageRequestV2, IIMCallback)`
- 环境自检三绿，`模块已生效 · 最近心跳 Ns 前`
- 删除时 **不再** 出现 `岛 end(reply) rc=9`；
  取而代之是 `岛未就绪(WAITING)，暂存 end(reply)` → `岛 end(reply) 补发成功`
- 流式卡片上**只有**「删除会话」按钮，没有「停止会话」

---

## 8. 附：本报告相关文件

- `android/app/src/main/java/com/islandbridge/IslandBridge.kt` — `endItem()` / `pendingEnds` / `flushPendingEnds()`
- `android/app/src/main/java/com/islandbridge/xposed/MessageSender.kt` — 删 interrupt 整套；`asSelfSend` / `selfSend`
- `android/app/src/main/java/com/islandbridge/xposed/DoubaoHookEntry.kt` — 删 ACT_STOP；心跳 `src` 标记
- `android/app/src/main/java/com/islandbridge/EnvCheck.kt` — 环境自检（新增）
- `android/app/src/main/java/com/islandbridge/MainActivity.kt` — 沉浸式 + 自检卡片 + `SHOW_PC_CONFIG`
- `android/app/src/main/java/com/islandbridge/Receivers.kt` — 只认 `src=doubao` 的心跳
- `android/app/libs/astraisland-client.aar` — `rc=9` 语义来源
- `REPORT_interrupt_chain.md` — DEX 侧 interrupt 调用链原始追踪（现已无功能用途，留作真身/空壳对照参考）
