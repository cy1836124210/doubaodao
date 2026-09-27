package com.islandbridge

import android.os.SystemClock
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * 运行环境自检：手机是否已 root、LSPosed 是否装好并跑着、以及最关键的一条
 * —— 本模块到底有没有真的被加载进豆包。
 *
 * 为什么要 root 才能查：普通 App 读不了 /data/adb。这是内核级 SELinux 拒绝，
 * 不是权限没申请。本机实测：`run-as com.islandbridge ls /data/adb`
 * → Permission denied。所以静态检测统一走一次 `su -c`。
 *
 * 唯一不需要 root 的证据是「模块心跳」：只有豆包进程里的 DoubaoHookEntry 会发
 * com.islandbridge.KEEPALIVE，因此只要时间戳是新的，就说明 LSPosed 确实把模块
 * 加载进了 com.larus.nova —— 这比任何静态文件检查都更有说服力（静态检查只能
 * 证明 LSPosed 装过，证明不了作用域勾对、证明不了豆包被注入了）。
 */
object EnvCheck {

    /** 结果缓存，避免每次 onResume 都 fork 一次 su。 */
    @Volatile private var cached: Env? = null
    @Volatile private var cachedAt = 0L
    private const val CACHE_MS = 5_000L

    /** 模块最后一次心跳（elapsedRealtime），0 = 从未。由 KeepAliveReceiver 写入。 */
    @Volatile private var lastModulePing = 0L

    private const val PREFS = "envcheck"
    private const val K_PING_ELAPSED = "ping_elapsed"
    private const val K_PING_WALL = "ping_wall"

    /** 记录一次模块心跳。落盘保存 —— 否则每次冷启动都从 0 开始，
     *  即使模块一直好好的，界面也会先报一次「尚未收到心跳」。 */
    fun noteModulePing() {
        val now = SystemClock.elapsedRealtime()
        lastModulePing = now
        try {
            BridgeApp.instance?.getSharedPreferences(PREFS, 0)?.edit()
                ?.putLong(K_PING_ELAPSED, now)
                ?.putLong(K_PING_WALL, System.currentTimeMillis())
                ?.apply()
        } catch (_: Throwable) {}
    }

    /** 距上次模块心跳的秒数；从未收到过返回 null。
     *  冷启动时 elapsedRealtime 会归零，所以内存值不可信，要拿落盘的
     *  墙钟时间反推。 */
    fun moduleAgeSec(): Long? {
        val p = BridgeApp.instance?.getSharedPreferences(PREFS, 0)
        val wall = p?.getLong(K_PING_WALL, 0L) ?: 0L
        if (wall > 0L) {
            val age = (System.currentTimeMillis() - wall) / 1000L
            return age.coerceAtLeast(0L)
        }
        val t = lastModulePing
        if (t == 0L) return null
        return ((SystemClock.elapsedRealtime() - t) / 1000L).coerceAtLeast(0L)
    }

    /** 心跳多久算「掉线」。模块在豆包存活时每 60s 打一次，给 3 个周期余量。 */
    private const val STALE_SEC = 180L

    data class Check(val ok: Boolean, val label: String, val detail: String)

    data class Env(
        /** 是否真的拿到了 uid=0（而不是只看到 su 文件存在）。 */
        val root: Check,
        /** root 管理器类型：KernelSU / Magisk / APatch / 未知。 */
        val rootMgr: String,
        /** LSPosed 框架：已安装 + 版本 + lspd 进程在跑。 */
        val lsposed: Check,
        /** 本模块是否真的被注入豆包（心跳证据）。 */
        val module: Check,
        /** 豆包进程是否存活。 */
        val doubao: Boolean,
    ) {
        /** 三项全绿才算「环境齐了」。 */
        val allOk: Boolean get() = root.ok && lsposed.ok && module.ok
    }

    fun cached(): Env? = cached

    /** 后台线程调用；内部会 fork 一次 su（可能弹 root 授权框）。 */
    fun probe(force: Boolean = false): Env {
        val now = SystemClock.elapsedRealtime()
        if (!force) {
            val c = cached
            if (c != null && now - cachedAt < CACHE_MS) return c
        }
        val env = runProbe()
        cached = env
        cachedAt = now
        return env
    }

    private fun runProbe(): Env {
        // 一次 su 调用把要看的都取回来，减少 root 授权次数
        val script = buildString {
            append("echo __ID__; id 2>&1; ")
            append("echo __SU__; ls /system/bin/su /system/xbin/su " +
                "/sbin/su /debug_ramdisk/su 2>/dev/null; ")
            append("echo __MGR__; ")
            append("[ -d /data/adb/ksu ] && echo KernelSU; ")
            append("[ -d /data/adb/magisk ] && echo Magisk; ")
            append("[ -d /data/adb/ap ] && echo APatch; ")
            append("echo __LSPD__; ls -d /data/adb/lspd 2>/dev/null; ")
            append("echo __LSPROP__; cat /data/adb/modules/zygisk_lsposed/" +
                "module.prop 2>/dev/null; ")
            append("echo __LSPDPROC__; pidof lspd 2>/dev/null; ")
            append("echo __DB__; grep -ac islandbridge " +
                "/data/adb/lspd/config/modules_config.db 2>/dev/null; ")
            append("echo __DOUBAO__; pidof com.larus.nova 2>/dev/null; ")
            append("echo __END__")
        }
        val out = sh(script)

        // su 没拿到（未授权 / 超时 / 无 root）时退回不需要 root 的弱证据
        if (out == null) return fallbackNoRoot()

        val sec = section(out)
        val idLine = sec["__ID__"].orEmpty()
        val gotRoot = idLine.contains("uid=0")
        val suFiles = sec["__SU__"].orEmpty().trim()
        val mgr = sec["__MGR__"].orEmpty().let { m ->
            when {
                m.contains("KernelSU") -> "KernelSU"
                m.contains("Magisk") -> "Magisk"
                m.contains("APatch") -> "APatch"
                else -> if (gotRoot) "自定义 root" else ""
            }
        }

        val root = if (gotRoot) {
            Check(true, "已 root", "uid=0" + if (mgr.isNotEmpty()) " · $mgr" else "")
        } else {
            Check(false, "未 root",
                if (suFiles.isNotEmpty()) "检测到 su 文件但无法提权（未授权？）"
                else "su 不可用")
        }

        val lspdDir = sec["__LSPD__"].orEmpty().trim()
        val prop = sec["__LSPROP__"].orEmpty()
        val lspdProc = sec["__LSPDPROC__"].orEmpty().trim()
        val dbHit = sec["__DB__"].orEmpty().trim().toIntOrNull() ?: 0
        val ver = Regex("version=(.+)").find(prop)?.groupValues?.get(1)?.trim()

        val lsposed = when {
            lspdDir.isEmpty() && prop.isEmpty() ->
                Check(false, "未安装 LSPosed", "找不到 /data/adb/lspd")
            lspdProc.isEmpty() ->
                Check(false, "LSPosed 未运行", "lspd 进程不在" +
                    (ver?.let { " · $it" } ?: ""))
            else -> Check(true, "LSPosed 已运行",
                (ver ?: "版本未知") +
                    if (dbHit > 0) " · 已登记本模块" else " · 未登记本模块")
        }

        val doubao = sec["__DOUBAO__"].orEmpty().trim().isNotEmpty()
        val module = moduleCheck(lsposed.ok, doubao)
        return Env(root, mgr, lsposed, module, doubao)
    }

    /** 心跳是本模块最强证据：只有被注入豆包才会发。 */
    private fun moduleCheck(lsposedOk: Boolean, doubaoAlive: Boolean): Check {
        val age = moduleAgeSec()
        return when {
            age != null && age <= STALE_SEC ->
                Check(true, "模块已生效", "最近心跳 ${age}s 前")
            age != null ->
                Check(false, "模块心跳已超时", "上次 ${age}s 前（>${STALE_SEC}s）")
            !lsposedOk ->
                Check(false, "模块未生效", "需先装好 LSPosed")
            !doubaoAlive ->
                Check(false, "尚未收到心跳", "打开一次豆包即可确认")
            else ->
                Check(false, "尚未收到心跳", "豆包在跑但模块没发声：\n" +
                    "  确认 LSPosed 里已勾选\n  com.larus.nova 作用域")
        }
    }

    /** 没有 root 时的弱检查：只看得到文件，证明不了提权。 */
    private fun fallbackNoRoot(): Env {
        val suVisible = listOf("/system/bin/su", "/system/xbin/su", "/sbin/su")
            .any { File(it).exists() }
        val root = Check(false,
            if (suVisible) "疑似已 root" else "未 root",
            if (suVisible) "检测到 su，但未获授权（无法确认）" else "找不到 su")
        // /data/adb 对普通 App 是 Permission denied，读不到
        val lsposed = Check(false, "无法检测 LSPosed", "需要 root 才能查看")
        val module = moduleCheck(false, false)
        return Env(root, "", lsposed, module, false)
    }

    /** 把 `echo __KEY__; ...` 的输出切成 key -> 内容。
     *  注意 key 存的是整行（含下划线），调用方一律用 "__KEY__" 查。 */
    private fun section(out: String): Map<String, String> {
        val map = HashMap<String, String>()
        var key: String? = null
        val sb = StringBuilder()
        for (line in out.lines()) {
            val t = line.trim()
            val m = Regex("^__\\w+__$").find(t)
            if (m != null) {
                key?.let { map[it] = sb.toString().trim() }
                sb.setLength(0)
                key = m.value
            } else if (key != null) {
                sb.appendLine(line)
            }
        }
        key?.let { map[it] = sb.toString().trim() }
        return map
    }

    /**
     * 执行 `su -c <script>`。6 秒没回来就强杀 —— root 授权框没被点掉时，
     * waitFor 会一直挂着，不能让它卡住自检线程。
     */
    private fun sh(script: String, timeoutMs: Long = 6_000L): String? = try {
        val p = ProcessBuilder("su", "-c", script)
            .redirectErrorStream(true)
            .start()
        val sb = StringBuilder()
        val reader = Thread {
            try {
                p.inputStream.bufferedReader().forEachLine { sb.appendLine(it) }
            } catch (_: Throwable) {}
        }
        reader.isDaemon = true
        reader.start()
        if (!p.waitFor(timeoutMs, TimeUnit.MILLISECONDS)) {
            p.destroyForcibly()
            reader.join(300)
            null
        } else {
            reader.join(600)
            sb.toString()
        }
    } catch (_: Throwable) {
        null
    }
}
