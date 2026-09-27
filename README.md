# 豆包岛桥 · doubaodao

把**豆包 AI 的流式回复和计划任务**实时推送到手机**星河岛**（AstraFlow / 星流）灵动岛。

- **回复 → 岛卡片**：豆包每条流式回复实时滚动上岛，带豆包头像与会话名
- **计划进度 → 下载样式进度环**：按子任务完成数显示 `done/total`
- **任务开始/结束 → 岛展开/缩回**：开始自动展开，结束以 outro 收尾
- **卡片操作**：点卡片空白处打开豆包 / 「删除会话」直接删掉豆包里的会话
- **环境自检**：App 内直接显示 Root / LSPosed / 模块注入 三项状态

---

## 前提条件（重要）

本方案依赖 **LSPosed 注入豆包进程**抓取流式数据，不是普通 App 能实现的能力。
以下三层缺一不可：

| 层级 | 要求 | 说明 |
|---|---|---|
| 1. 系统 | **已 root + Zygisk + LSPosed** | 没有 LSPosed 则完全无法抓取 |
| 2. 宿主 | **星河岛 / AstraFlow** | 承载卡片的宿主，协议需 **≥ v5** |
| 3. 目标 | **豆包 `com.larus.nova`** | 当前适配版本 **15.1.0** |

装好后还需在 LSPosed 管理器里**启用本模块并勾选作用域**：

```
com.larus.nova    抓豆包流式数据
android           保活（system_server 侧定时唤醒）
```

> ⚠️ 改完作用域必须**强制停止并重启豆包**；`android` 作用域变更需重启手机。

---

## 安装

1. 安装 `doubaodao-v1.0.apk`
2. 打开 App，顶部「运行环境」应显示三项全绿：
   ```
   运行环境                          正常
   ● Root 权限     已 root · uid=0 · KernelSU
   ● LSPosed 框架  LSPosed 已运行 · v2.2.0 · 已登记本模块
   ● 模块状态      模块已生效 · 最近心跳 0s 前
   ```
3. 在 LSPosed 里启用模块、勾作用域，重启豆包
4. 打开豆包发一条消息，即可看到卡片上岛

> 「模块状态」需要**豆包活着且心跳到达**才会转绿（心跳 60s 一次）。
> 刚打开 App 若显示「尚未收到心跳」，稍等或点「重新检测」。
> 这是刻意的严格设计：静态文件检查只能证明「装过 LSPosed」，
> 心跳才能证明**模块真的注入进了豆包**。

---

## 环境自检说明

`/data/adb` 对普通 App 是**内核 SELinux 拒绝**（不是权限没申请），
因此静态检测统一走一次 `su -c`，一次取回：

```
id / su 路径 / /data/adb/{ksu,magisk,ap} /
/data/adb/lspd / zygisk_lsposed/module.prop /
pidof lspd / 模块登记 / pidof com.larus.nova
```

6 秒超时强杀，避免 root 授权框无人点击导致卡死。

**模块生效用的是心跳证据**：保活 ping 有两份（豆包进程内 + system_server），
system_server 那份在豆包死掉时也会发。所以 ping 带上来源标记，
**只有 `src=doubao` 才算数**——避免作用域没勾也显示「已生效」的假绿。

---

## 构建

```bash
cd android
./gradlew :app:assembleDebug
# 产物：app/build/outputs/apk/debug/app-debug.apk
```

要求 JDK 17。依赖 `app/libs/` 下的两个本地库：

- `astraisland-client.aar` —— 星河岛接入 SDK（宿主协议 ≥ v5）
- `api-82.jar` —— classic Xposed API stub

---

## 目录结构

```
android/     手机端（Kotlin）：岛 SDK 投送 + SSE 订阅 + WebView 回复页 + LSPosed 模块
  app/src/main/java/com/islandbridge/
    MainActivity.kt          主界面：环境自检卡片 + 沉浸式状态栏
    EnvCheck.kt              运行环境自检（root / LSPosed / 模块心跳）
    IslandBridge.kt          事件 → 岛内容项映射；endItem() / pendingEnds 补发
    BridgeApp.kt             应用入口，装配 island/bridge/chat/link
    BridgeService.kt         前台保活服务 + root 中继安装
    EventProvider.kt         Binder 投递端点（绕开 ColorOS 冻结）
    Receivers.kt             保活 / 事件 / 开机自启接收器
    xposed/
      DoubaoHookEntry.kt     LSPosed 入口：hook 豆包 HTTP 流 + 命令广播
      MessageSender.kt       发送 / 删除会话（真实 IM 调用）
      MobileFeedParser.kt    流式数据解析
pc/          电脑端（Python）：CDP 抓豆包桌面端 → 归一化 → SSE 广播
tools/       逆向与调试脚本
pylibs/      Python 依赖（websocket-client）
```

---

## 已知限制

- **豆包没有「停止」功能**：其 UI 无停止按钮，`OmniBreakReason_CLICK_BREAK_BUTTON`
  从 UI 侧不可达。因此本模块**不提供停止动作**，相关代码已移除。
- **豆包升级可能失效**：深度依赖豆包内部混淆类名（`OmniMessageService`、
  `NativeMessageServiceImpl` 等），版本升级可能改名导致 hook 失效。
- **电脑端连接配置暂时隐藏**：`MainActivity.SHOW_PC_CONFIG = false`，
  改为 `true` 即恢复「电脑IP / 端口 + 连接 / 断开」。后台连接逻辑不受影响。
- 本项目仅供学习研究，请遵守相关软件的服务条款。

---

## 修复记录

详见 [`STOP_DELETE_FIX.md`](STOP_DELETE_FIX.md)。其中记录了三个真机实测确认的 bug：

1. **删除后岛里残留内容** —— `island.end()` 早于 session 绑定发出，
   返回 `rc=9`（无 Binder session）被静默丢弃，旧代码却照清账面，
   导致岛仍渲染旧卡片直到 60s 到期。已用 `pendingEnds` 队列 + 补发修复。
2. **发送自我投毒** —— 捕获 hook 连自己的出站调用一起抓，
   首次被服务端拒的废包成为模板，污染后续所有发送。已用 `asSelfSend` 隔离。
3. **心跳来源混淆** —— system_server 的 ping 被误当模块生效证据，
   会造成「假绿」。已按来源标记区分。
