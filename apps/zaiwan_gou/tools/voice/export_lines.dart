// 把超时来电的全部台词打成 JSON（原文，带语气词），给 make_voice.py 生成语音用。
// 台词只有 lib/features/call/call_script.dart 一份。用法：dart tools/voice/export_lines.dart
import 'dart:convert';
import 'dart:io';

import 'package:zwjsg_app/features/call/call_script.dart';
import 'package:zwjsg_app/features/call/call_voice.dart';

void main() {
  stdout.write(jsonEncode({
    'voices': [for (final v in CallVoice.values) v.name],
    'lines': [for (final line in CallScript.all) {'text': line, 'file': clipName(line)}],
  }));
}
