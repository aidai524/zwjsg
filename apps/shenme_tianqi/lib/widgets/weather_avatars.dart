import 'dart:ui' as ui;

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/widgets.dart';

import '../core/app_state.dart';

/// 用户自己的天气形象：导入了“再玩我是狗”的形象，就用照片贴纸叠天气图层；没导入就用代码画的默认形象
class MyWeatherAvatar extends StatelessWidget {
  const MyWeatherAvatar({super.key, required this.temp, required this.cond, this.size = 220});

  final WeatherTemp temp;
  final WeatherCond cond;
  final double size;

  @override
  Widget build(BuildContext context) {
    final sticker = AppScope.of(context).avatar;
    return sticker == null
        ? WeatherAvatar(temp: temp, cond: cond, size: size)
        : PhotoWeatherAvatar(sticker: sticker, temp: temp, cond: cond, size: size);
  }
}

/// 关心群里别人的天气形象：TA 导入过形象就下载下来叠天气图层；没导入、还没下载好、下载不到时用默认形象
class MemberWeatherAvatar extends StatefulWidget {
  const MemberWeatherAvatar({super.key, required this.avatarUrl, required this.temp, required this.cond, this.size = 72});

  final String? avatarUrl;
  final WeatherTemp temp;
  final WeatherCond cond;
  final double size;

  @override
  State<MemberWeatherAvatar> createState() => _MemberWeatherAvatarState();
}

class _MemberWeatherAvatarState extends State<MemberWeatherAvatar> {
  Future<ui.Image?>? _sticker;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(MemberWeatherAvatar old) {
    super.didUpdateWidget(old);
    if (old.avatarUrl != widget.avatarUrl) _load();
  }

  void _load() {
    final url = widget.avatarUrl;
    // 同一个地址只下载一次，见 AppState.memberAvatar
    _sticker = url == null ? null : AppScope.read(context).memberAvatar(url);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image?>(
      future: _sticker,
      builder: (_, snap) {
        final sticker = snap.data;
        return sticker == null
            ? WeatherAvatar(temp: widget.temp, cond: widget.cond, size: widget.size)
            : PhotoWeatherAvatar(sticker: sticker, temp: widget.temp, cond: widget.cond, size: widget.size);
      },
    );
  }
}
