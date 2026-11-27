package com.zwjsg.zwjsg_app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * 单个 App 超时的“来电”：用满每天的额度后，狗版的你打来一个语音电话（2026-11-23 起是 Flutter 画的、像 FaceTime 的来电界面，
 * 和 iOS 共用 lib/features/call/call_screen.dart）。单独的任务栈、单独的 Flutter 引擎，入口是 main.dart 的 callMain。
 * - 响铃、震动：拒接 = 这个限时今天锁死（明天 0 点解开）；接听后它说几句，学两声狗叫再玩 10 分钟，或者挂断不玩了
 * - 今天拒接过，再打开那个 App 直接是“今天锁死了”（[EXTRA_LOCKED]），不响铃
 * Flutter 引擎启动要一会儿，这边一打开就先用手机自己的来电铃声响起来、震动。
 * App 名称只显示在这一页上；念出来的话里不带 App 名称（系统的语音引擎可能是第三方的）。不上传任何东西。
 */
class CallReminderActivity : FlutterActivity() {

    companion object {
        const val EXTRA_LABEL = "label"
        const val EXTRA_LIMIT = "limit"

        /** 按狗度来的限时：狗度到了多少（%）；按额度的是 0 */
        const val EXTRA_DOG_PERCENT = "dogPercent"
        const val EXTRA_USED = "used"
        const val EXTRA_LOCK_ID = "lockId"

        /** 今天拒接过：直接是“今天锁死了” */
        const val EXTRA_LOCKED = "locked"
    }

    private var plugin: CallPlugin? = null

    override fun getDartEntrypointFunctionName(): String = "callMain"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        plugin = CallPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!intent.getBooleanExtra(EXTRA_LOCKED, false)) plugin?.ring()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        plugin?.onPermissionResult(requestCode, grantResults)
    }

    override fun onStop() {
        super.onStop()
        // 切走了就别一直响、一直说、一直听；回来时 Flutter 会再叫响铃
        plugin?.pause()
    }

    override fun onDestroy() {
        plugin?.dispose()
        plugin = null
        super.onDestroy()
    }
}
