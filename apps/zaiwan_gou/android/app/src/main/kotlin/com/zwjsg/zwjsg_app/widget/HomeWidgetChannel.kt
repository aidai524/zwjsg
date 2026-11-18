package com.zwjsg.zwjsg_app.widget

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 桌面小组件的通道（Flutter 那边是 lib/core/home_widget.dart）：
 * 把狗度规则、目标和数据来源交给小组件；告诉 Flutter 形象图放在哪个目录；形象图换了、狗度变了让小组件重画。
 */
object HomeWidgetChannel {
    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, "zwjsg/home_widget").setMethodCallHandler { call, result ->
            when (call.method) {
                "directory" -> {
                    val dir = DogWidgetStore.avatarDir(app).apply { mkdirs() }
                    result.success(dir.absolutePath)
                }
                "configure" -> {
                    DogWidgetStore.saveConfig(app, call.arguments as? Map<*, *>)
                    DogWidgetProvider.refreshAll(app)
                    result.success(null)
                }
                "reload" -> {
                    DogWidgetProvider.refreshAll(app)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
