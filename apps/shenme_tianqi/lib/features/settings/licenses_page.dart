import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

/// App 的版本：照 pubspec.yaml 的 version（去掉 + 后面的构建号），开源许可页头上显示。测试会对一遍
const appVersion = '0.1.0';

/// “设置 › 开源许可”（2026-11-26）：系列共用的许可页（pop_ui 的 [showPopLicenses]），列的是 Dart 包的许可。
/// 天气 App 没有打包 Dart 包以外的第三方模型、字体、素材（天气动画是代码画的）；以后打包了，
/// 像狗 App 的 lib/core/licenses.dart 那样在 main() 里用 LicenseRegistry.addLicense 补上
Future<void> showAppLicenses(BuildContext context) => showPopLicenses(
      context,
      appName: '什么鬼天气',
      version: appVersion,
      iconAsset: 'assets/icon/icon_full.png',
    );
