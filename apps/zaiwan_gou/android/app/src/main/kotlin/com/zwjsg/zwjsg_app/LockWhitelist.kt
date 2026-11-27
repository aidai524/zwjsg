package com.zwjsg.zwjsg_app

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import android.provider.Telephony
import android.telecom.TelecomManager

/**
 * 超时来电的白名单（2026-11-27）：电话、短信、地图、支付、银行和系统设置永远不来电，也选不进限时。
 * 系统默认的电话、短信 App 和系统标成“地图”的 App 自动算；国内常见的支付、银行、地图 App 按包名认。
 * 系统设置也放进来：限时出了问题，总得能进设置把无障碍关掉。
 */
object LockWhitelist {
    private val KNOWN = setOf(
        "com.android.settings", // 系统设置
        "com.android.dialer", "com.google.android.dialer", "com.android.contacts", "com.android.incallui", // 电话
        "com.android.mms", "com.google.android.apps.messaging", // 短信
        "com.autonavi.minimap", "com.baidu.BaiduMap", "com.tencent.map", "com.huawei.maps.app", // 地图
        "com.google.android.apps.maps",
        "com.eg.android.AlipayGphone", "com.unionpay", // 支付宝、云闪付
        "com.icbc", "com.chinamworld.main", "com.android.bankabc", "com.chinamworld.bocmbci", // 工行、建行、农行、中行
        "cmb.pb", "com.bankcomm.Bankcomm", "com.yitong.mbank.psbc", // 招行、交行、邮储
    )

    fun contains(context: Context, pkg: String): Boolean {
        if (pkg in KNOWN) return true
        if (pkg == defaultDialer(context) || pkg == defaultSms(context)) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val info = try {
                context.packageManager.getApplicationInfo(pkg, 0)
            } catch (e: Exception) {
                return false
            }
            if (info.category == ApplicationInfo.CATEGORY_MAPS) return true
        }
        return false
    }

    private fun defaultDialer(context: Context): String? =
        runCatching { (context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager).defaultDialerPackage }
            .getOrNull()

    private fun defaultSms(context: Context): String? = runCatching { Telephony.Sms.getDefaultSmsPackage(context) }.getOrNull()
}
