import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 设计规范：黄黑波普。对应 UI 设计画布里的「设计规范」画板。
class Pop {
  Pop._();

  static const yellow = Color(0xFFFFD23F);
  static const ink = Color(0xFF1B1B1F);
  static const white = Color(0xFFFFFFFF);
  static const gray = Color(0xFFF3F4F6);
  static const muted = Color(0xFF5F6368);

  /// 黄底上的次要文字，保证对比度
  static const mutedOnYellow = Color(0xFF3A3A30);
  static const softYellow = Color(0xFFFFF4C2);
  static const rareBlue = Color(0xFF2F6BFF);
  static const legendGold = Color(0xFFE8A317);
  static const kingRed = Color(0xFFE5484D);
  static const danger = Color(0xFFC62828);

  static const double stroke = 3;
  static const Offset shadowOffset = Offset(4, 4);
  static const double radius = 20;

  /// 状态栏样式，按页面底色选。透明底 + 图标明暗，不动导航栏，和 AppBar 的默认做法一致。
  static const overlayOnLight = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark, // 安卓
    statusBarBrightness: Brightness.light, // iOS
  );
  static const overlayOnDark = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light, // 安卓
    statusBarBrightness: Brightness.dark, // iOS
  );

  static BoxDecoration card({Color color = white, double radius = Pop.radius, bool shadow = true, Color border = ink}) =>
      BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border, width: stroke),
        boxShadow: shadow ? const [BoxShadow(color: ink, offset: shadowOffset)] : null,
      );

  /// 标题字体：上线前换成已授权的圆体，在 pubspec.yaml 的 fonts 里注册后改这里
  static const String? titleFont = null;

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: yellow, primary: ink, surface: white),
      scaffoldBackgroundColor: white,
      splashFactory: NoSplash.splashFactory,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink, fontFamily: titleFont),
      appBarTheme: const AppBarTheme(
        // 背景透明时 Flutter 会按深色背景算，选白色图标，所以要明确指定。深色页面单独覆盖
        systemOverlayStyle: overlayOnLight,
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class PopText {
  PopText._();
  static const hero = TextStyle(fontSize: 60, fontWeight: FontWeight.w900, height: 1.02, color: Pop.ink);
  static const title = TextStyle(fontSize: 30, fontWeight: FontWeight.w900, height: 1.25, color: Pop.ink);
  static const h2 = TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Pop.ink);
  static const body = TextStyle(fontSize: 15, height: 1.6, color: Pop.ink);
  static const bodyMuted = TextStyle(fontSize: 15, height: 1.6, color: Pop.muted);
  static const small = TextStyle(fontSize: 13, color: Pop.muted);
  static const label = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Pop.muted);
}
