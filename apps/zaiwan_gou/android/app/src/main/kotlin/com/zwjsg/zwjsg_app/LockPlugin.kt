package com.zwjsg.zwjsg_app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * App 时间锁：Flutter 管理锁（增删改、选 app），拦截由 [LockAccessibilityService] 做。
 * 隐私约定：app 名称、图标和用时只交给 Flutter 在手机上显示，不上传。
 */
class LockPlugin(private val context: Context) {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val store = LockStore(context)

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "zwjsg/locks").setMethodCallHandler { call, result ->
            when (call.method) {
                "isServiceEnabled" -> result.success(isServiceEnabled())
                "openServiceSettings" -> {
                    context.startActivity(
                        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }
                "listLocks" -> background(result) { locksPayload() }
                "saveLock" -> {
                    val packages = call.argument<List<String>>("packages").orEmpty()
                    val minutes = call.argument<Int>("minutes") ?: 0
                    val id = call.argument<String>("id") ?: LockStore.newId()
                    val locks = store.all()
                    when {
                        packages.isEmpty() || minutes <= 0 -> result.error("bad_args", "先选要锁的 App", null)
                        locks.none { it.id == id } && locks.size >= LockStore.MAX ->
                            result.error("too_many", "最多 ${LockStore.MAX} 个时间锁", null)
                        else -> {
                            store.save(AppLock(id, packages, minutes))
                            background(result) { locksPayload() }
                        }
                    }
                }
                "deleteLock" -> {
                    call.argument<String>("id")?.let(store::delete)
                    background(result) { locksPayload() }
                }
                "launchableApps" -> background(result) { launchableApps() }
                else -> result.notImplemented()
            }
        }
    }

    /** 要算用时、读图标，放到后台线程，结果回主线程 */
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        Thread {
            val outcome = runCatching(work)
            mainHandler.post {
                outcome.fold({ result.success(it) }, { result.error("LOCK_FAILED", it.message, null) })
            }
        }.start()
    }

    private fun locksPayload(): List<Map<String, Any?>> {
        val today = if (TodayUsage.hasPermission(context)) TodayUsage.compute(context) else null
        return store.all().map { lock ->
            val usedMs = today?.let { LockStore.usedMs(lock, it) }
            val graceActive = usedMs != null && store.graceRemainingMs(lock.id, usedMs) > 0
            mapOf(
                "id" to lock.id,
                "packages" to lock.packages,
                "labels" to lock.packages.map { TodayUsage.label(context, it) },
                "minutes" to lock.minutes,
                "usedMinutes" to usedMs?.let(TodayUsage::toMin),
                "locked" to (usedMs != null && usedMs >= lock.minutes * 60_000L && !graceActive),
                "graceActive" to graceActive,
            )
        }
    }

    /** 能锁的 app：桌面上有图标的，去掉自己和桌面；今天用得多的排前面 */
    private fun launchableApps(): List<Map<String, Any?>> {
        val ignored = TodayUsage.ignoredPackages(context)
        val today = if (TodayUsage.hasPermission(context)) TodayUsage.compute(context) else null
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return context.packageManager.queryIntentActivities(launcher, 0)
            .map { it.activityInfo.packageName }
            .distinct()
            .filter { it !in ignored }
            .map { pkg -> Triple(pkg, TodayUsage.label(context, pkg), today?.foregroundMs?.get(pkg) ?: 0L) }
            .sortedWith(compareByDescending<Triple<String, String, Long>> { it.third }.thenBy { it.second })
            .map { (pkg, label, ms) ->
                mapOf(
                    "package" to pkg,
                    "label" to label,
                    "minutes" to TodayUsage.toMin(ms),
                    "icon" to TodayUsage.iconPng(context, pkg),
                )
            }
    }

    private fun isServiceEnabled(): Boolean {
        val enabled = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
            ?: return false
        val me = ComponentName(context, LockAccessibilityService::class.java)
        return enabled.split(':').any { ComponentName.unflattenFromString(it) == me }
    }
}
