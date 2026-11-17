package com.zwjsg.zwjsg_app

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** App 时间锁的拦截页：被锁的 App 用满额度后，无障碍服务退回桌面并打开这一页 */
class LockedActivity : Activity() {

    companion object {
        const val EXTRA_LABEL = "label"
        const val EXTRA_MINUTES = "minutes"
        const val EXTRA_LOCK_ID = "lockId"
        const val EXTRA_PACKAGE = "package"
        const val EXTRA_GRACE_LEFT = "graceLeft"

        // 和 Flutter 那边的黄黑波普配色一致
        private val INK = Color.parseColor("#1B1B1F")
        private val YELLOW = Color.parseColor("#FFD23F")

        fun formatMinutes(m: Int) = when {
            m < 60 -> "$m 分钟"
            m % 60 == 0 -> "${m / 60} 小时"
            else -> "${m / 60} 小时 ${m % 60} 分"
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val label = intent.getStringExtra(EXTRA_LABEL) ?: "这个 App"
        val minutes = intent.getIntExtra(EXTRA_MINUTES, 0)
        val dp = resources.displayMetrics.density

        fun text(value: String, sizeSp: Float, bold: Boolean, topDp: Int) = TextView(this).apply {
            text = value
            textSize = sizeSp
            setTextColor(INK)
            gravity = Gravity.CENTER
            if (bold) typeface = Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = (topDp * dp).toInt() }
        }

        val button = Button(this).apply {
            text = "算了，不刷了"
            textSize = 17f
            setTextColor(YELLOW)
            typeface = Typeface.DEFAULT_BOLD
            isAllCaps = false
            background = GradientDrawable().apply {
                setColor(INK)
                cornerRadius = 28 * dp
            }
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, (56 * dp).toInt())
                .apply { topMargin = (36 * dp).toInt() }
            setOnClickListener { goHome() }
        }

        // 紧急解锁：防止锁太死被卸载。每天几次，每次再用几分钟，用满自动再拦
        val lockId = intent.getStringExtra(EXTRA_LOCK_ID)
        val pkg = intent.getStringExtra(EXTRA_PACKAGE)
        val graceLeft = intent.getIntExtra(EXTRA_GRACE_LEFT, 0)
        val graceButton = Button(this).apply {
            text = if (graceLeft > 0) {
                "还是要刷 ${LockStore.GRACE_MINUTES} 分钟（今天还剩 $graceLeft 次）"
            } else {
                "今天的临时解锁用完了"
            }
            isEnabled = graceLeft > 0 && lockId != null && pkg != null
            textSize = 15f
            setTextColor(INK)
            isAllCaps = false
            setBackgroundColor(Color.TRANSPARENT)
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, (48 * dp).toInt())
                .apply { topMargin = (8 * dp).toInt() }
            setOnClickListener { grantAndReopen(lockId!!, pkg!!) }
        }

        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(YELLOW)
            setPadding((32 * dp).toInt(), 0, (32 * dp).toInt(), 0)
            addView(text("汪！", 56f, true, 0))
            addView(text("「$label」今天用满 ${formatMinutes(minutes)} 了", 22f, true, 16))
            addView(text("明天 0 点自动解锁。想改额度，打开“再玩我是狗 › App 时间锁”。", 15f, false, 12))
            addView(button)
            addView(graceButton)
        })
    }

    private fun grantAndReopen(lockId: String, pkg: String) {
        val store = LockStore(this)
        val lock = store.all().firstOrNull { it.id == lockId }
        val used = if (lock != null && TodayUsage.hasPermission(this)) LockStore.usedMs(lock, TodayUsage.compute(this)) else 0L
        if (lock == null || !store.grantGrace(lockId, used)) return goHome()
        packageManager.getLaunchIntentForPackage(pkg)?.let { startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        finish()
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun onBackPressed() = goHome()

    private fun goHome() {
        startActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        finish()
    }
}
