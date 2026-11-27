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
 * 设了限时的 App 一打开就看今天用了多久：用满了就弹出来电页（狗版的你打来的），盖在那个 App 上面；
 * 还没用满就记下剩余时间，到点还在用就来电。接了电话学两声狗叫再玩 10 分钟，到点再来电；
 * 拒接了今天就锁死：再打开直接是“今天锁死了”，点“好”回桌面（2026-11-23）。
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
        if (LockWhitelist.contains(this, pkg)) {
            // 电话、支付这些永远不来电；切过去时，上一个 App 的倒计时也不用再等了
            pendingCheck?.let(handler::removeCallbacks)
            pendingCheck = null
            return
        }
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
            if (store.isDeclinedToday(lock.id)) return call(pkg, lock, LockStore.usedMs(lock, today), locked = true)
            val used = LockStore.usedMs(lock, today)
            // 按额度：这些 App 合计还差多久；按狗度：今天一共还差多久刷到那个狗度（还不知道目标就不打）
            val left = store.leftMs(lock, today) ?: continue
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
            return call(pkg, lock, used, locked = false)
        }
        // 还没用满：到点再看一眼，人还在这个 App 里就来电
        val recheck = Runnable { if (foreground == pkg) check(pkg) }
        pendingCheck = recheck
        handler.postDelayed(recheck, soonest + 1_000L)
    }

    /**
     * 来电页盖在那个 App 上面，不退回桌面；放行了回到那个 App，拒接、挂断才回桌面。
     * [locked]：今天拒接过，直接是“今天锁死了”。每次都开一个新的来电页（清掉上一次留下的）
     */
    private fun call(pkg: String, lock: AppLock, usedMs: Long, locked: Boolean) {
        startActivity(
            Intent(this, CallReminderActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                .putExtra(CallReminderActivity.EXTRA_LABEL, TodayUsage.label(this, pkg))
                .putExtra(CallReminderActivity.EXTRA_LIMIT, lock.minutes)
                .putExtra(CallReminderActivity.EXTRA_DOG_PERCENT, lock.dogPercent ?: 0)
                .putExtra(CallReminderActivity.EXTRA_USED, TodayUsage.toMin(usedMs))
                .putExtra(CallReminderActivity.EXTRA_LOCK_ID, lock.id)
                .putExtra(CallReminderActivity.EXTRA_LOCKED, locked)
        )
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
