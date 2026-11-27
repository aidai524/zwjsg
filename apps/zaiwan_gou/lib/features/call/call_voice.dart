import 'dart:convert';

import 'call_script.dart';

/// 狗版的你的声音（2026-11-23）：用户在“超时来电”页自己挑，默认 [spirit]。
///
/// 台词（[CallScript]）提前用 MiniMax 语音合成生成、加好电话音效，打包在 `assets/voice/<name>/` 里，来电时不联网。
/// 生成：`tools/voice/make_voice.py`（每个声音的 MiniMax 音色 ID 和语速在那里，目录名就是这里的 [name]；
/// 测试会检查每句台词在每个声音下都有文件，改了台词要重新跑一遍）。
/// 声音是 AI 合成的：来电界面和挑声音的地方都写明“AI 合成语音”，文件里也带了 AIGC 元数据。
enum CallVoice {
  spirit('憨憨萌兽'),
  boy('可爱男生'),
  girl('俏皮女生');

  const CallVoice(this.label);

  final String label;

  static const fallback = CallVoice.spirit;

  /// 存在手机上的名字读回来；没存过、认不出都用默认
  static CallVoice byName(String? name) => values.firstWhere((v) => v.name == name, orElse: () => fallback);

  /// 挑声音时试听的那句
  static String get sample => CallScript.open.first;

  /// 这句台词（原文，带语气词）在这个声音下的资源路径
  String asset(String line) => 'assets/voice/$name/${clipName(line)}.m4a';
}

/// 语音文件名：台词原文（带语气词）UTF-8 的 FNV-1a 32 位哈希。台词一改文件名就跟着变，
/// `tools/voice/make_voice.py` 用同样的算法
String clipName(String line) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(line)) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}
