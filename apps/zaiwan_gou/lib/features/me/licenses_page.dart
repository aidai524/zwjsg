import 'package:flutter/material.dart';
import 'package:pop_ui/pop_ui.dart';

/// App 的版本：照 pubspec.yaml 的 version（去掉 + 后面的构建号），开源许可页头上显示。测试会对一遍
const appVersion = '0.1.0';

/// “我的 › 开源许可”（2026-11-26）：系列共用的许可页（pop_ui 的 [showPopLicenses]）。
/// Dart 包以外、打包进 App 的模型和运行库见 core/licenses.dart 的 AppLicenses
Future<void> showAppLicenses(BuildContext context) => showPopLicenses(
      context,
      appName: '再玩我是狗',
      version: appVersion,
      iconAsset: 'assets/icon/icon_full.png',
      legalese: 'App 里用到的开源软件和模型，以及它们的许可证',
    );
