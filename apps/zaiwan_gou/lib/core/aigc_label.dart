import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// AI 生成内容的隐式标识。
///
/// 《人工智能生成合成内容标识办法》（2025-09-01 施行）要求导出、分享的 AI 生成图片在文件元数据里带隐式标识。
/// 字段照 GB 45438-2025《网络安全技术 人工智能生成合成内容标识方法》的“文件元数据隐式标识”：
/// Label（1 表示属于 AI 生成合成内容）、ContentProducer（生成合成服务提供者的名称或编码）、ProduceID（内容编号）、
/// ReservedCode1、ContentPropagator、PropagateID、ReservedCode2（传播方的字段由传播平台自己写，这里留空）。
/// 写成 PNG 的 iTXt 块：关键字 AIGC，内容是 UTF-8 的 JSON，放在 IEND 前面。
/// 上线前请法务确认格式，ContentProducer 换成公司名称或备案号。
class AigcLabel {
  AigcLabel._();

  static const keyword = 'AIGC';

  /// 生成合成服务提供者：先写 App 名，公司和备案号定了再换
  static const producer = '再玩我是狗';

  static const _signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  /// 给 PNG 加上隐式标识；不是完整的 PNG 时原样返回（宁可少个标识，也不能把图弄坏）
  static Uint8List embed(Uint8List png, {String? produceId}) {
    final iend = _findIend(png);
    if (iend == null) return png;
    final json = jsonEncode({
      'Label': '1',
      'ContentProducer': producer,
      'ProduceID': produceId ?? _newId(),
      'ReservedCode1': '',
      'ContentPropagator': '',
      'PropagateID': '',
      'ReservedCode2': '',
    });
    final data = BytesBuilder()
      ..add(latin1.encode(keyword))
      ..add([0, 0, 0]) // 关键字结束、不压缩、压缩方式
      ..add([0, 0]) // 语言标签、翻译后的关键字都留空
      ..add(utf8.encode(json));
    final chunk = _chunk('iTXt', data.takeBytes());
    return Uint8List.fromList([...png.sublist(0, iend), ...chunk, ...png.sublist(iend)]);
  }

  /// 读出 PNG 里的 AIGC 信息；没有时返回 null
  static Map<String, dynamic>? read(Uint8List png) {
    if (!_isPng(png)) return null;
    var p = 8;
    while (p + 12 <= png.length) {
      final length = _u32(png, p);
      final type = latin1.decode(png.sublist(p + 4, p + 8));
      if (p + 12 + length > png.length) return null;
      if (type == 'iTXt') {
        final data = png.sublist(p + 8, p + 8 + length);
        final end = data.indexOf(0);
        if (end > 0 && latin1.decode(data.sublist(0, end)) == keyword) {
          // 关键字 \0 压缩标志 压缩方式 语言标签\0 翻译关键字\0 正文
          var i = end + 3;
          i = data.indexOf(0, i) + 1;
          i = data.indexOf(0, i) + 1;
          return jsonDecode(utf8.decode(data.sublist(i))) as Map<String, dynamic>;
        }
      }
      p += 12 + length;
    }
    return null;
  }

  static bool _isPng(Uint8List png) {
    if (png.length < 8) return false;
    for (var i = 0; i < 8; i++) {
      if (png[i] != _signature[i]) return false;
    }
    return true;
  }

  /// IEND 块的起点；文件不完整时返回 null
  static int? _findIend(Uint8List png) {
    if (!_isPng(png)) return null;
    var p = 8;
    while (p + 12 <= png.length) {
      final length = _u32(png, p);
      if (latin1.decode(png.sublist(p + 4, p + 8)) == 'IEND') return p;
      p += 12 + length;
    }
    return null;
  }

  static int _u32(Uint8List b, int p) => (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3];

  static List<int> _chunk(String type, List<int> data) {
    final body = [...latin1.encode(type), ...data];
    final crc = crc32(body);
    final length = data.length;
    return [
      (length >> 24) & 0xFF, (length >> 16) & 0xFF, (length >> 8) & 0xFF, length & 0xFF, //
      ...body,
      (crc >> 24) & 0xFF, (crc >> 16) & 0xFF, (crc >> 8) & 0xFF, crc & 0xFF,
    ];
  }

  static final List<int> _crcTable = List.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  @visibleForTesting
  static int crc32(List<int> bytes) {
    var c = 0xFFFFFFFF;
    for (final b in bytes) {
      c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFF;
  }

  /// 内容编号：时间 + 随机数，同一张卡每次导出都不一样
  static String _newId() {
    final r = math.Random.secure();
    final tail = List.generate(6, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return 'zwjsg-${DateTime.now().millisecondsSinceEpoch}-$tail';
  }
}
