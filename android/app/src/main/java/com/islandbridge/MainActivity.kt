package com.islandbridge

import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.webkit.WebView
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import org.json.JSONObject

class MainActivity : Activity() {
    private lateinit var app: BridgeApp
    private lateinit var web: WebView
    private lateinit var status: TextView

    // 环境自检的三行（root / LSPosed / 模块）
    private lateinit var dotRoot: TextView
    private lateinit var txtRoot: TextView
    private lateinit var dotLsp: TextView
    private lateinit var txtLsp: TextView
    private lateinit var dotMod: TextView
    private lateinit var txtMod: TextView
    private lateinit var envSummary: TextView

    companion object {
        /** 电脑端（SSE）连接配置：暂时不显示。改为 true 即可恢复
         *  「电脑IP / 端口 + 连接 / 断开」那一行，其余逻辑无需改动
         *  （BridgeService 仍会按已保存的 prefs 自动重连）。 */
        private const val SHOW_PC_CONFIG = false

        private val BG = Color.parseColor("#14161a")
        private val TXT = Color.parseColor("#e8eaf0")
        private val DIM = Color.parseColor("#9aa0ab")
        private val OK = Color.parseColor("#3fce8a")
        private val BAD = Color.parseColor("#ff5c5c")
        private val WARN = Color.parseColor("#ffb020")
        private val ACCENT = Color.parseColor("#4d7cfe")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        app = application as BridgeApp
        // 从 Android 15 起系统强制全面屏（edge-to-edge）。这里显式声明并存底，
        // 状态栏/导航栏交给下面的 Insets 监听去留白，否则内容会钻到状态栏底下。
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        WindowInsetsControllerCompat(window, window.decorView).apply {
            isAppearanceLightStatusBars = false   // 深色底色 → 浅色图标
            isAppearanceLightNavigationBars = false
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(BG)
        }

        // 顶部标题
        root.addView(TextView(this).apply {
            text = "豆包岛桥"
            setTextColor(TXT); textSize = 19f
            setPadding(dp(20), dp(14), dp(20), dp(2))
        })

        // ---- 环境自检卡片 ----
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#1e2126"))
                cornerRadius = dp(12).toFloat()
            }
            setPadding(dp(14), dp(12), dp(14), dp(12))
        }
        val head = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        head.addView(TextView(this).apply {
            text = "运行环境"
            setTextColor(TXT); textSize = 15f
            layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
        })
        envSummary = TextView(this).apply {
            setTextColor(DIM); textSize = 12f
        }
        head.addView(envSummary)
        card.addView(head)

        txtRoot = addCheckRow(card, "Root 权限", "正在检测…")
        txtLsp = addCheckRow(card, "LSPosed 框架", "正在检测…")
        txtMod = addCheckRow(card, "模块状态", "正在检测…")

        card.addView(Button(this).apply {
            text = "重新检测"
            setOnClickListener { refreshEnv(force = true) }
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
                .apply { topMargin = dp(10) }
        })
        root.addView(card, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            .apply { setMargins(dp(16), dp(10), dp(16), 0) })

        // ---- 电脑端连接配置（暂时隐藏；SHOW_PC_CONFIG=true 恢复）----
        if (SHOW_PC_CONFIG) {
            val prefs = getSharedPreferences("bridge", MODE_PRIVATE)
            val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            val hostEt = EditText(this).apply {
                hint = "电脑IP"
                setText(prefs.getString("host", "192.168.1.2"))
                layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 2f)
            }
            val portEt = EditText(this).apply {
                hint = "端口"
                inputType = android.text.InputType.TYPE_CLASS_NUMBER
                setText(prefs.getInt("port", 8787).toString())
                layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
            }
            row.addView(hostEt); row.addView(portEt)
            root.addView(row, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
                .apply { setMargins(dp(16), dp(8), dp(16), 0) })
            val pcBtn = LinearLayout(this)
            fun pcBtnAdd(label: String, f: () -> Unit) = pcBtn.addView(
                Button(this).apply {
                    text = label; setOnClickListener { f() }
                    layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
                })
            pcBtnAdd("连接") {
                val host = hostEt.text.toString().trim()
                val port = portEt.text.toString().toIntOrNull() ?: 8787
                prefs.edit().putString("host", host).putInt("port", port).apply()
                BridgeService.start(this)
                app.connectTo(host, port)
            }
            pcBtnAdd("断开") { app.disconnect() }
            root.addView(pcBtn)
        }

        // ---- 岛状态 + 测试按钮 ----
        status = TextView(this).apply {
            text = "未连接"; setTextColor(DIM); textSize = 13f
            setPadding(dp(20), dp(12), dp(20), dp(4))
        }
        root.addView(status)

        val btnRow = LinearLayout(this)
        fun btn(label: String, f: () -> Unit) = btnRow.addView(
            Button(this).apply {
                text = label; setOnClickListener { f() }
                layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
            })
        btn("岛状态") {
            val e = EnvCheck.cached()
            Toast.makeText(this,
                "岛: ${app.island.state}" +
                    if (e != null) "\n环境: " + (if (e.allOk) "正常" else "待处理")
                    else "",
                Toast.LENGTH_SHORT).show()
        }
        btn("测试进度") {
            app.bridge.handle(JSONObject(
                """{"t":"plan.start","tid":"t1","title":"演示任务"}"""))
            app.bridge.handle(JSONObject(
                """{"t":"plan.progress","done":1,"total":2,"name":"步骤一"}"""))
        }
        btn("测试歌词") {
            app.bridge.handle(JSONObject("""{"t":"chat.start","mid":"m1"}"""))
            app.bridge.handle(JSONObject(
                """{"t":"chat.delta","mid":"m1","kind":"think","text":"正在理解任务要求"}"""))
        }
        btn("结束测试") {
            app.bridge.handle(JSONObject(
                """{"t":"plan.end","success":true,"text":"任务完成"}"""))
            app.bridge.handle(JSONObject("""{"t":"chat.end","mid":"m1"}"""))
        }
        root.addView(btnRow)

        // ---- 回复页 ----
        web = WebView(this).apply {
            settings.javaScriptEnabled = true
            setBackgroundColor(BG)
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f)
            loadUrl("file:///android_asset/chat/chat.html")
        }
        root.addView(web)

        val replyRow = LinearLayout(this)
        val replyEt = EditText(this).apply {
            hint = "回复豆包…"
            layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
        }
        replyRow.addView(replyEt)
        replyRow.addView(Button(this).apply {
            text = "发送"
            setOnClickListener {
                val t = replyEt.text.toString().trim()
                if (t.isEmpty()) return@setOnClickListener
                app.bridge.sendReply(t)
                replyEt.setText("")
            }
        })
        root.addView(replyRow)

        setContentView(root)

        // 关键：把系统栏/刘海/键盘的高度变成内容内边距，否则顶部会被状态栏压住
        ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val sys = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or
                    WindowInsetsCompat.Type.displayCutout())
            val ime = insets.getInsets(WindowInsetsCompat.Type.ime())
            v.setPadding(sys.left, sys.top, sys.right,
                maxOf(sys.bottom, ime.bottom))
            WindowInsetsCompat.CONSUMED
        }

        if (Build.VERSION.SDK_INT >= 33) {
            requestPermissions(
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1)
        }

        app.link.onState = { s -> runOnUiThread { status.text = s } }
        app.chat.listener = { o ->
            runOnUiThread {
                val safe = JSONObject.quote(o.toString())
                web.evaluateJavascript("window.onBridgeMsg($safe)", null)
            }
        }

        refreshEnv(force = false)
    }

    override fun onResume() {
        super.onResume()
        // 豆包起来后心跳才会到，回前台时顺手复查一次
        refreshEnv(force = false)
    }

    /** 一行的「圆点 + 标题 + 详情」。圆点引用回填到 dotXxx，返回详情 TextView。 */
    private fun addCheckRow(parent: LinearLayout, title: String,
                           initial: String): TextView {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(8), 0, 0)
        }
        val dot = TextView(this).apply {
            text = "●"; setTextColor(DIM); textSize = 13f
            setPadding(0, dp(2), dp(8), 0)
        }
        // 把圆点挂到对应的字段上
        when (title) {
            "Root 权限" -> dotRoot = dot
            "LSPosed 框架" -> dotLsp = dot
            else -> dotMod = dot
        }
        row.addView(dot)
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        col.addView(TextView(this).apply {
            text = title; setTextColor(TXT); textSize = 14f
        })
        val detail = TextView(this).apply {
            text = initial; setTextColor(DIM); textSize = 12f
        }
        col.addView(detail)
        row.addView(col)
        parent.addView(row)
        return detail
    }

    private fun applyRow(dot: TextView, detail: TextView,
                         c: EnvCheck.Check) {
        dot.setTextColor(when {
            c.ok -> OK
            c.detail.contains("疑似") || c.detail.contains("尚未") ||
                c.detail.contains("超时") -> WARN
            else -> BAD
        })
        detail.text = c.label + if (c.detail.isNotEmpty()) " · ${c.detail}" else ""
    }

    private fun refreshEnv(force: Boolean) {
        envSummary.text = "检测中…"
        Thread {
            val e = EnvCheck.probe(force)
            runOnUiThread {
                applyRow(dotRoot, txtRoot, e.root)
                applyRow(dotLsp, txtLsp, e.lsposed)
                applyRow(dotMod, txtMod, e.module)
                val summary = when {
                    e.allOk -> "正常"
                    !e.root.ok -> "缺 root"
                    !e.lsposed.ok -> "缺 LSPosed"
                    else -> "模块未生效"
                }
                envSummary.text = summary
                envSummary.setTextColor(if (e.allOk) OK else WARN)
            }
        }.start()
    }

    private fun dp(v: Int): Int =
        (v * resources.displayMetrics.density).toInt()
}
