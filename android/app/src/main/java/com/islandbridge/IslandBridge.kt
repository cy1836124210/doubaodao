package com.islandbridge

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.astraisland.client.IslandClient
import com.astraisland.protocol.ActivityBundle
import org.json.JSONObject

/** Maps bridge events onto island content items.
 *
 *  plan.*  -> "plan"    LIVE_UPDATE + PROGRESS (下载样式进度环)
 *  chat.*  -> "reply"   MESSAGE 通知卡片      (和包式卡片：图标+标题+正文+按钮)
 *    - 标题  "手机-会话名" / "电脑-会话名"
 *    - 正文  回复流式滚动（body）
 *    - 按钮  回复 / 删除会话
 *    - 点击卡片 -> 打开豆包 App（openIntent）
 *  chat.reply 只进回复页，不上岛（协议预留）。
 */
class IslandBridge(private val ctx: Context,
                   private val island: IslandClient,
                   private val log: (String) -> Unit = {}) {

    companion object {
        const val ID_PLAN = "plan"
        const val ID_REPLY = "reply"
        const val BODY_MAX = 512
        /** 展开卡片的正文长度（推流中）。docs/INTEGRATION 第七节：MESSAGE 的
         *  body 固定「两行」，不是滚动区，超长只从开头截断。所以推流期间必须
         *  只发「最新的一段」——否则那两行永远停在回复的开头，看起来像卡死。
         *  两行大约放得下这么多字；宁短勿长，一旦超出被截掉的正是最新内容。 */
        const val EXPAND_MAX = 48
        /** 回复结束后改发完整正文，按阅读顺序从头开始。正文单字段上限 4096
         *  字，但全部文本合计只有 8 KB（UTF-8）——中文一字 3 字节，取 2000
         *  留足余量，避免整体超限被截。 */
        const val FINAL_MAX = 2000
        // 胶囊信息区状态文案（岛外不展开时只显示这个）
        const val ST_REPLYING = "正在回复"
        const val ST_DONE = "回答完毕"
        const val ST_THINKING = "正在思考"
        const val PKG_DOUBAO = "com.larus.nova"
        const val ACT_OPEN_DOUBAO = "com.islandbridge.OPEN_DOUBAO"
        const val ACT_DELETE = "delete"
        const val ACT_ACK = "ack"
        // broadcasts INTO the doubao process (module's dynamic receiver)
        const val BCAST_SEND = "com.islandbridge.SEND"
        const val BCAST_DELETE = "com.islandbridge.DELETE"
        const val DISMISS_AFTER_MS = 60_000L   // 最后一次更新起 1 分钟自消
        const val SEND_TIMEOUT_MS = 1_500L     // 等豆包进程回执的时长
    }

    private val main = Handler(Looper.getMainLooper())

    // body throttle: island coalesces updates within 250ms anyway, so pushing
    // faster than that only wastes Binder calls. 200ms keeps the pill visibly
    // live without tripping the island's 10-updates/sec allowance.
    private var pendingBody: String? = null
    private val flush = Runnable {
        pendingBody?.let { pushReplyItem(it) }
        pendingBody = null
    }
    private var replyShown = false
    private var planTitle = "计划任务"
    private var replyTitle = "豆包"           // conversation name (no prefix)
    private var replySrc = "手机"            // "手机" / "电脑" — title prefix
    private var replyStartedAt = 0L          // wall clock for the timestamp
    private val convNames = HashMap<String, String>()

    private val liveIds = HashSet<String>()   // ids already started on island
    private val replyBuf = StringBuilder()    // accumulated reply text
    private var replySuppressed = false       // 操作过后本 mid 不再上岛
    private var lastDropLog = 0L

    fun resync() {
        // island (re)connected.
        //
        // Do NOT clear our bookkeeping here. On a cold Binder wake this runs
        // AFTER the first chat.start already arrived (the provider call starts
        // the process, the island handshake finishes a moment later), so
        // wiping replyShown/replyBuf made the eventual chat.end update a silent
        // no-op — the guard saw replyShown=false and the pill stayed on
        // 「正在回复」 forever while the body was already thrown away.
        //
        // Re-publish what we currently believe is live instead. Any stashed
        // copy of the same id is now redundant (last write wins), so drop it.
        synchronized(pending) { pending.remove(ID_REPLY) }
        if (replyShown && !replySuppressed) {
            pushReplyItem(replyBuf.toString(), status = ST_REPLYING)
        }
        flushPending()
        flushPendingEnds()
    }

    /** Events that arrived before the island session finished binding.
     *
     *  This is the normal case after a cold Binder wake: the provider call
     *  starts the process, the island handshake is still WAITING when the
     *  first plan/chat frame lands, and the old code dropped it — so the
     *  card never appeared. Hold the newest bundle per id and replay on ready.
     *  Bounded: island allows max 3 live items / 10 starts per second. */
    private val pending = LinkedHashMap<String, android.os.Bundle>()

    private fun flushPending() {
        if (!island.isReady || pending.isEmpty()) return
        val replay = ArrayList(pending.entries)
        pending.clear()
        for ((id, b) in replay) {
            val rc = island.start(b)
            if (rc == 0) {
                liveIds.add(id)
                synchronized(pendingEnds) { pendingEnds.remove(id) }
            } else log("岛补发($id) rc=$rc")
        }
        if (replay.isNotEmpty()) log("岛就绪，补发 ${replay.size} 条")
    }

    /** Replay ends that could not be delivered earlier (see pendingEnds).
     *  Runs on the same onReadyChanged edge as flushPending. */
    private fun flushPendingEnds() {
        if (!island.isReady) return
        val ids = synchronized(pendingEnds) {
            if (pendingEnds.isEmpty()) return
            val c = ArrayList(pendingEnds); pendingEnds.clear(); c
        }
        for (id in ids) {
            val rc = island.end(id)
            if (rc != 0) {
                synchronized(pendingEnds) { pendingEnds.add(id) }
                log("岛 end($id) 重试仍失败 rc=$rc")
            } else {
                log("岛 end($id) 补发成功")
            }
        }
    }

    private var replyCid = ""
    /** botId of the current conversation, required by deleteConversation. */
    private var replyBotId = ""

    fun handle(o: JSONObject, fromMobile: Boolean = false) {
        // learn conversation titles; adopt the title of the current chat
        val cname = o.optString("cname")
        val cid = o.optString("cid")
        if (cname.isNotBlank() && cid.isNotBlank()) convNames[cid] = cname
        o.optString("botId").let { if (it.isNotBlank()) replyBotId = it }
        if (o.optString("t").startsWith("chat.") && cid.isNotBlank()) {
            replyCid = cid
            replyTitle = (if (cname.isNotBlank()) cname
                          else convNames[cid]) ?: "豆包"
        }
        when (o.optString("t")) {
            "chat.conv" -> {
                if (cid.isNotBlank() && cid == replyCid) replyTitle = cname
            }
            "plan.start" -> {
                planTitle = o.optString("title").ifBlank { "计划任务" }
                pushPlan(0, 0, planTitle)
            }
            "plan.progress" -> {
                val done = o.optInt("done"); val total = o.optInt("total")
                pushPlan(done, total, o.optString("name").ifBlank { planTitle })
            }
            "plan.end" -> {
                liveIds.remove(ID_PLAN)
                endItem(ID_PLAN, o.optString("text").ifBlank { "任务完成" },
                    success = o.optBoolean("success", true))
            }
            "chat.start" -> {
                replySrc = if (fromMobile) "手机" else "电脑"
                replyStartedAt = System.currentTimeMillis()
                replyShown = true
                replySuppressed = false
                replyBuf.setLength(0)
                // 胶囊只显示状态，所以第一帧就给「正在回复」
                pushReplyItem("", status = ST_REPLYING)
            }
            "chat.delta" -> {
                if (replySuppressed) return
                val kind = o.optString("kind")
                val text = o.optString("text")
                if (kind == "text") {
                    // 正文累积进 buffer；上岛时只取最新一段（见 pushReplyItem）
                    replyBuf.append(text)
                    stageBody(replyBufTail())
                } else if (text.isNotBlank()) {
                    // think/tool 状态行 —— 胶囊显示思考中，正文给出提示
                    stageBody(text)
                }
            }
            "chat.async" -> stageBody("已转为后台任务，岛上继续跟进")
            "chat.end" -> {
                // 不主动 end：卡片留下，按钮换成「我知道了」，等操作或
                // 60s 无更新自动消失
                pendingBody = null
                main.removeCallbacks(flush)
                if (replyShown && !replySuppressed) {
                    // 结束时发完整正文，并把胶囊状态改成「回答完毕」
                    pushReplyItem(replyBuf.toString(),
                        ended = true, status = ST_DONE)
                }
            }
            "send.result" -> onSendResult(o.optBoolean("ok"),
                o.optString("err"), o.optString("act"))
            // "chat.reply" 全量文本 —— 协议预留，暂不接入岛
        }
    }

    /** Action-button taps on the island card arrive here via IslandClient. */
    fun onAction(id: String, action: String) {
        when (action) {
            "open" -> openDoubao()
            ACT_DELETE -> {
                log("岛动作:删除会话")
                if (replySrc == "手机") {
                    // previously this only dismissed the card — the IM stack was
                    // never touched, so the conversation survived. Now it is a
                    // real deleteConversation, with the same
                    // submit → receipt → timeout scaffolding as send/stop.
                    armPending("删除失败，已取消")
                    ctx.sendBroadcast(Intent(BCAST_DELETE)
                        .setPackage(PKG_DOUBAO)
                        .putExtra("cid", replyCid)
                        .putExtra("botId", replyBotId))
                } else {
                    // PC-side conversations are not on this device's IM stack
                    log("电脑侧会话无法在本机删除")
                    dismissReply("已删除")
                }
            }
            ACT_ACK -> {
                log("岛动作:我知道了")
                dismissReply(null)
            }
        }
    }

    /** v6 回复输入条 / App 回复页输入框 —— 把文字真正发回豆包。
     *  路由：卡片来自手机(LSPosed)就进豆包进程内 sendMessageV2；
     *  来自电脑就 POST 给 PC daemon 用 CDP 注入。两边都失败才回退到
     *  剪贴板+拉起豆包的老路子。 */
    fun onReplyText(id: String, text: String) {
        sendReply(text)
    }

    fun sendReply(text: String) {
        if (text.isBlank()) return
        log("回复[$replySrc-$replyTitle]: ${text.take(60)}")
        pendingSendText = text
        if (replySrc == "手机") sendViaMobile(text) else sendViaPc(text)
    }

    private fun sendViaMobile(text: String) {
        lastSendErr = ""
        ctx.sendBroadcast(Intent(BCAST_SEND)
            .setPackage(PKG_DOUBAO)
            .putExtra("text", text)
            .putExtra("cid", replyCid))
        log("已递交豆包进程发送，等待回执…")
        val rt = Runnable {
            log(if (lastSendErr.isNotEmpty())
                    "进程内发送失败: $lastSendErr — 回退剪贴板"
                else "豆包进程无回执，回退剪贴板")
            fallbackSend(pendingSendText) }
        pendingTimeout = rt
        main.postDelayed(rt, SEND_TIMEOUT_MS)
    }

    private fun sendViaPc(text: String) {
        val app = ctx.applicationContext as? BridgeApp
        if (app == null) { fallbackSend(text); return }
        app.link.postReply(text, replyCid) { ok, detail ->
            main.post {
                if (ok) {
                    log("已发送到电脑豆包")
                    dismissReply("已发送")
                } else {
                    log("电脑侧发送失败: $detail")
                    fallbackSend(text)
                }
            }
        }
    }

    /** send.result event back from the LSPosed hook inside Doubao.
     *  Doubao has several processes and each may answer — a failure is NOT
     *  final: keep the timeout alive, remember the error, and only fall back
     *  when the timeout fires with no success. A success resolves instantly. */
    fun onSendResult(ok: Boolean, err: String, act: String) {
        if (!ok) {
            lastSendErr = err
            log("send.result[$act] 失败: $err")
            return
        }
        pendingTimeout?.let { main.removeCallbacks(it) }
        pendingTimeout = null
        when (act) {
            BCAST_DELETE -> { dismissReply("已删除"); return }
        }
        log("已发送到手机豆包")
        dismissReply("已发送")
    }

    /** 老路径兜底：复制进剪贴板并拉起豆包（粘贴即得）。 */
    private fun fallbackSend(text: String) {
        try {
            val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE)
                as android.content.ClipboardManager
            cm.setPrimaryClip(android.content.ClipData.newPlainText(
                "豆包回复", text))
        } catch (t: Throwable) { log("剪贴板失败: $t") }
        openDoubao()
        dismissReply("已交给应用发送")
    }

    private var pendingTimeout: Runnable? = null
    private var pendingSendText = ""
    private var lastSendErr = ""

    /** Shared scaffolding for stop/delete: if no receipt arrives within
     *  SEND_TIMEOUT_MS, surface `fallbackText` instead of silently pretending
     *  the operation succeeded (that is how delete "worked" before while the
     *  conversation quietly survived). */
    private fun armPending(fallbackText: String) {
        pendingTimeout?.let { main.removeCallbacks(it) }
        val rt = Runnable { pendingTimeout = null; dismissReply(fallbackText) }
        pendingTimeout = rt
        main.postDelayed(rt, SEND_TIMEOUT_MS)
    }

    /** 卡片空白处点击（经 OpenDoubaoReceiver）：打开豆包，卡片消失。 */
    fun cardTapped() {
        openDoubao()
        dismissReply(null)
    }

    /** The user swiped the card away on the island side (or it expired) —
     *  resync our bookkeeping so the next chat.start re-creates it cleanly. */
    fun userDismissed(id: String) {
        if (id == ID_REPLY) {
            pendingBody = null
            main.removeCallbacks(flush)
            replyBuf.setLength(0)
            replyShown = false
            replySuppressed = true
        }
        liveIds.remove(id)
    }

    /** Remove the reply card after an operation (tap/reply/delete).
     *  outro == null → 立即消失；否则先显示一句话再收。 */
    private fun dismissReply(outro: String?) {
        pendingBody = null
        main.removeCallbacks(flush)
        replyBuf.setLength(0)
        liveIds.remove(ID_REPLY)
        replyShown = false
        replySuppressed = true
        endItem(ID_REPLY, outro)
    }

    /** ids whose end() has NOT yet reached the island.
     *
     *  BUG THIS FIXES (live-proven): IslandClient.send() returns rc=9 when its
     *  Binder `session` is null — i.e. the call never left the process — and
     *  `island` is often still WAITING at the moment a card is dismissed. In
     *  the captured logs every single one of 11 `end(reply)` calls returned
     *  rc=9, yet the old code cleared replyShown/liveIds regardless. Our
     *  bookkeeping said "gone" while the island kept rendering the stale card
     *  (the 已删除 conversation's content lingered) until its 60s expiry.
     *  Now a failed end is parked here and replayed on the next onReadyChanged,
     *  so the card really goes away. */
    private val pendingEnds = HashSet<String>()

    /** End an island item, deferring the call when there is no live session. */
    private fun endItem(id: String, outro: String?, success: Boolean = true) {
        if (!island.isReady) {
            synchronized(pending) { pending.remove(id) }
            synchronized(pendingEnds) { pendingEnds.add(id) }
            log("岛未就绪(${island.state})，暂存 end($id)")
            return
        }
        val rc = if (outro == null) island.end(id)
        else island.end(id, ActivityBundle.encodeOutro(success = success, text = outro))
        if (rc != 0) {
            // rc=9 == no session; anything else is an island-side refusal.
            // Park it either way — a stale card is worse than a late retry.
            synchronized(pendingEnds) { pendingEnds.add(id) }
            log("岛 end($id) rc=$rc，已排队重试")
        } else {
            synchronized(pendingEnds) { pendingEnds.remove(id) }
        }
    }

    /** Card tap / 回复 button: open the Doubao app. */
    fun openDoubao() {
        try {
            val i = ctx.packageManager.getLaunchIntentForPackage(PKG_DOUBAO)
                ?: ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
                ?: return
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(i)
        } catch (t: Throwable) {
            log("打开豆包失败: $t")
        }
    }

    /** body shows the reply tail — full text while short, last chars once long */
    private fun replyBufTail(): String {
        val s = replyBuf.toString()
        return if (s.length <= BODY_MAX - 32) s else s.takeLast(BODY_MAX - 32)
    }

    /** Last [max] chars, preferring to start right after a sentence/word
     *  boundary so the tail reads as whole sentences instead of mid-word.
     *
     *  Why the tail and not the head: the island treats a `start()` with an
     *  already-known id as a FULL replacement (PROTOCOL.md: same id = 整份替换),
     *  and an over-long string is marquee-scrolled from position 0
     *  (INTEGRATION.md: 放不下时连续滚动). Streaming re-sends the item every
     *  few hundred ms, so the marquee restarts before it can finish a pass and
     *  the newest tokens never reach the screen — the card looks stuck on the
     *  opening words. Keeping the payload short enough to FIT means no scroll
     *  and no truncation, so the newest text is what is on screen. */
    private fun tailOf(s0: String, max: Int): String {
        val s = s0.trim()
        if (s.length <= max) return s
        var cut = s.length - max
        val stops = charArrayOf('\n', '。', '！', '？', '；', '，',
                                '.', '!', '?', ';', ',', ' ')
        // only nudge forward a little; never eat more than a third of the tail
        val lim = minOf(s.length - 1, cut + max / 3)
        var i = cut
        while (i < lim) {
            if (s[i] in stops) { cut = i + 1; break }
            i++
        }
        return "…" + s.substring(cut)
    }

    private fun stageBody(line: String) {
        pendingBody = line.take(BODY_MAX)
        if (!main.hasCallbacks(flush)) main.postDelayed(flush, 300)
    }

    // ---------- Doubao app icon / launch intent ----------

    /** Ship the real Doubao launcher icon to the island (bitmap), with the
     *  package name attached so the host can re-resolve if it prefers. */
    private val doubaoIcon: android.os.Bundle by lazy {
        try {
            val d = ctx.packageManager.getApplicationIcon(PKG_DOUBAO)
            ActivityBundle.encodeIcon("bitmap",
                packageName = PKG_DOUBAO, bitmap = drawableToBitmap(d))
        } catch (t: Throwable) {
            ActivityBundle.encodeIcon("builtin", builtin = "MESSAGE")
        }
    }

    private fun drawableToBitmap(d: Drawable): Bitmap {
        if (d is BitmapDrawable && d.bitmap != null && !d.bitmap.isRecycled)
            return d.bitmap
        val sz = 192
        val b = Bitmap.createBitmap(sz, sz, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        d.setBounds(0, 0, sz, sz)
        d.draw(c)
        return b
    }

    /** Whole-card tap -> OpenDoubaoReceiver：打开豆包并按「操作过即消失」
     *  收起卡片（直接起 Activity 拿不到回调，只能走广播）。 */
    private val openIntent: PendingIntent by lazy {
        val i = Intent(ACT_OPEN_DOUBAO).setPackage(ctx.packageName)
        PendingIntent.getBroadcast(ctx, 0, i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    /** start() == update() in this client lib; returns nonzero when the
     *  island session isn't there. A cold Binder wake lands here while the
     *  handshake is still WAITING, so stash the newest bundle per id and
     *  replay it once onReadyChanged fires — dropping it loses the card. */
    private fun send(id: String, bundle: android.os.Bundle): Int {
        if (!island.isReady) {
            synchronized(pending) {
                // keep at most 3 live ids, mirroring the island's own quota
                if (pending.size >= 3 && !pending.containsKey(id)) {
                    pending.remove(pending.keys.first())
                }
                pending[id] = bundle
            }
            val now = SystemClock.elapsedRealtime()
            if (now - lastDropLog > 5000) {
                lastDropLog = now
                log("岛未就绪(${island.state})，暂存 $id")
            }
            return -1
        }
        val rc = island.start(bundle)
        if (rc != 0) log("岛 start($id) rc=$rc")
        else {
            // a fresh start supersedes any parked end for this id — replaying
            // it later would kill the card we just created
            synchronized(pendingEnds) { pendingEnds.remove(id) }
        }
        return rc
    }

    private fun pushPlan(done: Int, total: Int, step: String) {
        val fraction = if (total > 0) done.toFloat() / total else 0f
        val first = liveIds.add(ID_PLAN)
        send(ID_PLAN, ActivityBundle.encodeActivity(
            id = ID_PLAN,
            kind = "LIVE_UPDATE",
            priority = 60,               // 外部来源上限 60(与未到点计时同档)
            hideWhenSourceForeground = false,   // 默认 true:本 App 前台会退副岛
            compactLeading = ActivityBundle.encodeSlot("icon",
                icon = ActivityBundle.encodeIcon("builtin", builtin = "DOWNLOAD")),
            compactTrailing = ActivityBundle.encodeSlot("ring", fraction = fraction),
            expanded = ActivityBundle.encodeExpanded(
                template = "PROGRESS",
                title = planTitle,
                subtitle = step,
                progress = ActivityBundle.encodeProgress(
                    fraction = fraction,
                    startLabel = if (total > 0) "$done/$total" else "…"),
                actions = arrayListOf(
                    ActivityBundle.encodeAction("open", "打开豆包岛桥")),
            ),
            alertOnStart = first,        // only the first push alerts
        ))
    }

    /** 通知式卡片。
     *
     *  三个区域分别对应三种需求：
     *  - 岛外(胶囊)不展开时：信息区只写状态「手机·正在回复」/「电脑·回答完毕」，
     *    让用户一眼看出是谁在答、答完没有，而不必读正文。
     *  - 展开卡片后：body 走推流。注意 MESSAGE 的 body 是**固定两行、不是滚动
     *    区**（docs/INTEGRATION 第七节），超长只从开头截断。所以推流期间发的是
     *    「最新一小段」(EXPAND_MAX)，最后一帧才换成完整正文从头读。
     *    若推流期间发长文，那两行会永远停在开头——正是之前"只看见最头的信息"
     *    的原因。
     *  - 电脑/手机字样：compactLabel 与 title 都带来源前缀。
     *
     *  排位说明（docs/INTEGRATION 第十二节）：kind=MESSAGE 按新消息处理，
     *  主岛只停留「消息主岛停留时长」(默认 6s) 就强制让位副岛——用户要求
     *  豆包活动期间永不退副岛，所以 kind 用 LIVE_UPDATE(没有让位规则，
     *  外部上限 priority 60)，展开仍用 MESSAGE 模板保住卡片样式和回复条。
     *  仍可能排到来电/导航/播放中音乐之后——外部来源天花板如此。 */
    private fun pushReplyItem(body: String, ended: Boolean = false,
                              status: String? = null) {
        val first = liveIds.add(ID_REPLY)
        val st = status ?: if (ended) ST_DONE else ST_REPLYING
        // 胶囊信息区：来源 + 状态。这里滚动是可接受的（岛外长文自动滚动是正常
        // 行为），所以不必截断成极短。
        val compact = "$replySrc·$st"
        // 展开正文：推流中「只有最新一段」，结束后给完整正文从头读。
        val expandedBody = if (ended) body.trim().take(FINAL_MAX)
                           else tailOf(body, EXPAND_MAX)
        log("岛card src=$replySrc st=$st body=${expandedBody.length}字")
        send(ID_REPLY, ActivityBundle.encodeActivity(
            id = ID_REPLY,
            kind = "LIVE_UPDATE",
            priority = 60,               // 外部来源上限
            compactLabel = "$replySrc-$replyTitle",   // 身份区图标旁的名称
            // 身份区：豆包头像
            compactLeading = ActivityBundle.encodeSlot("image",
                icon = doubaoIcon),
            // 信息区：只放状态，不放正文
            compactTrailing = ActivityBundle.encodeSlot("text",
                text = compact, scrollable = true),
            expanded = ActivityBundle.encodeExpanded(
                template = "MESSAGE",
                hero = doubaoIcon,      // hero 直接吃 encodeIcon，非 slot
                title = "$replySrc · $replyTitle",
                subtitle = st,
                body = expandedBody,
                reply = !ended,                    // 「回复 X」输入条(v6)
                actions = if (ended) arrayListOf(
                    ActivityBundle.encodeAction(ACT_ACK, "我知道了"))
                else arrayListOf(
                    ActivityBundle.encodeAction(ACT_DELETE, "删除会话",
                        destructive = true)),
            ),
            alertOnStart = first,
            openIntent = openIntent,                 // 点卡片空白处打开豆包
            postedAtWallMs = replyStartedAt,         // 标题旁「刚刚/X分钟前」
            dismissAfterMs = DISMISS_AFTER_MS,       // 无操作 60s 自动消失
            hideWhenSourceForeground = false,        // 前台也不退副岛
            contentDescription = "豆包回复 $replyTitle",
        ))
    }
}
