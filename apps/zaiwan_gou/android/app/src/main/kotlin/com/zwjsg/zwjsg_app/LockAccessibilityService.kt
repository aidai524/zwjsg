package com.zwjsg.zwjsg_app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.inputmethod.InputMethodManager

/**
 * App 时间锁的拦截：用户在系统“无障碍”里手动打开。
 * 只听“切换到哪个 App”的事件，不读屏幕内容，不记录操作。
 * 被锁的 App 一打开就看今天用了多久：用满了就退回桌面、弹出拦截页；还没用满就记下剩余时间，到点还在用就拦下。
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
            // 已经用满，但正在紧急解锁的 5 分钟里
            val grace = store.graceRemainingMs(lock.id, used)
            if (grace > 0) {
                soonest = minOf(soonest, grace)
                continue
            }
            return block(pkg, lock, store.graceLeft(lock.id))
        }
        // 还没用满：到点再看一眼，人还在这个 App 里就拦下
        val recheck = Runnable { if (foreground == pkg) check(pkg) }
        pendingCheck = recheck
        handler.postDelayed(recheck, soonest + 1_000L)
    }

    private fun block(pkg: String, lock: AppLock, graceLeft: Int) {
        performGlobalAction(GLOBAL_ACTION_HOME)
        startActivity(
            Intent(this, LockedActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(LockedActivity.EXTRA_LABEL, TodayUsage.label(this, pkg))
                .putExtra(LockedActivity.EXTRA_MINUTES, lock.minutes)
                .putExtra(LockedActivity.EXTRA_LOCK_ID, lock.id)
                .putExtra(LockedActivity.EXTRA_PACKAGE, pkg)
                .putExtra(LockedActivity.EXTRA_GRACE_LEFT, graceLeft)
        )
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
