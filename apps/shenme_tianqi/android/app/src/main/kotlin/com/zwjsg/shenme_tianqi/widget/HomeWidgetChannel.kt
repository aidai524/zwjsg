package com.zwjsg.shenme_tianqi.widget

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 桌面小组件的通道（Flutter 那边是 lib/core/home_widget.dart）：
 * 把常驻城市、温度单位交给小组件；告诉 Flutter 形象图放在哪个目录；形象图换了让小组件重画。
 */
object HomeWidgetChannel {
    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, "shenmetianqi/home_widget").setMethodCallHandler { call, result ->
            when (call.method) {
                "directory" -> {
                    val dir = WidgetStore.avatarDir(app).apply { mkdirs() }
                    result.success(dir.absolutePath)
                }
                "configure" -> {
                    WidgetStore.saveConfig(app, call.arguments as? Map<*, *>)
                    WeatherWidgetProvider.refreshAll(app)
                    result.success(null)
                }
                "reload" -> {
                    WeatherWidgetProvider.refreshAll(app)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
