package com.zwjsg.zwjsg_app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.inputmethod.InputMethodManager

/**
 * 单个 App 限时的“来电提醒”：用户在系统“无障碍”里手动打开。
 * 只听“切换到哪个 App”的事件，不读屏幕内容，不记录操作。
 * 设了限时的 App 一打开就看今天用了多久：用满了就弹出来电页（你的狗打来的），不退回桌面、不禁止；
 * 还没用满就记下剩余时间，到点还在用就来电。接了电话选“再玩 10 分钟”，到点再来电。
 */
class LockAccessibilityService : AccessibilityService() {

    private val handler = Handler(Looper.getMainLooper())
    private var pendingCheck: Runnable? = null
    private var foreground: String? = null

    /** 输入法、系统界面弹出来时，人其实还在原来的 App 里 */
    private val overlays: Set<String> by lazy {
        val ime = (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager)
            .enabledInputMethodList.map { it.packageName }
        (ime + "com.android.systemui").toSet()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg in overlays) return
        foreground = pkg
        if (pkg == packageName) return // 自己的页面（包括拦截页）
        check(pkg)
    }

    override fun onInterrupt() {}

    private fun check(pkg: String) {
        pendingCheck?.let(handler::removeCallbacks)
        pendingCheck = null
        val store = LockStore(this)
        val locks = store.all().filter { pkg in it.packages }
        if (locks.isEmpty() || !TodayUsage.hasPermission(this)) return

        val today = TodayUsage.compute(this)
        var soonest = Long.MAX_VALUE
        for (lock in locks) {
            val used = LockStore.usedMs(lock, today)
            val left = lock.minutes * 60_000L - used
            if (left > 0) {
                soonest = minOf(soonest, left)
                continue
            }
            // 已经用满，但正在“再玩 10 分钟”
            val grace = store.graceRemainingMs(lock.id, used)
            if (grace > 0) {
                soonest = minOf(soonest, grace)
                continue
            }
            return ring(pkg, lock, used)
        }
        // 还没用满：到点再看一眼，人还在这个 App 里就来电
        val recheck = Runnable { if (foreground == pkg) check(pkg) }
        pendingCheck = recheck
        handler.postDelayed(recheck, soonest + 1_000L)
    }

    /** 来电：盖在那个 App 上面，不退回桌面。挂断或“不玩了”才回桌面 */
    private fun ring(pkg: String, lock: AppLock, usedMs: Long) {
        startActivity(
            Intent(this, CallReminderActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(CallReminderActivity.EXTRA_LABEL, TodayUsage.label(this, pkg))
                .putExtra(CallReminderActivity.EXTRA_LIMIT, lock.minutes)
                .putExtra(CallReminderActivity.EXTRA_USED, TodayUsage.toMin(usedMs))
                .putExtra(CallReminderActivity.EXTRA_LOCK_ID, lock.id)
        )
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
