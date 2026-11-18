import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:series_share/series_share.dart';

/// 1x1 的 PNG
final onePixelPng =
    base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

void main() {
  test('导出的 PNG 里写上 AIGC 隐式标识，图本身不变；不是 PNG 时原样返回', () {
    final labeled = AigcLabel.embed(onePixelPng, producer: '什么鬼天气', produceId: 'zwjsg-1');
    expect(AigcLabel.read(labeled), {
      'Label': '1',
      'ContentProducer': '什么鬼天气',
      'ProduceID': 'zwjsg-1',
      'ReservedCode1': '',
      'ContentPropagator': '',
      'PropagateID': '',
      'ReservedCode2': '',
    });
    expect(AigcLabel.read(onePixelPng), isNull);
    // 原来的块原样保留，标识插在 IEND 前面
    expect(labeled.sublist(0, onePixelPng.length - 12), onePixelPng.sublist(0, onePixelPng.length - 12));
    expect(labeled.sublist(labeled.length - 12), onePixelPng.sublist(onePixelPng.length - 12));
    expect(AigcLabel.crc32(latin1.encode('IEND')), 0xAE426082);
    final junk = Uint8List.fromList([1, 2, 3]);
    expect(AigcLabel.embed(junk, producer: '再玩我是狗'), same(junk));
  });

  test('每次导出的内容编号都不一样', () {
    final a = AigcLabel.read(AigcLabel.embed(onePixelPng, producer: '再玩我是狗'))!['ProduceID'];
    final b = AigcLabel.read(AigcLabel.embed(onePixelPng, producer: '再玩我是狗'))!['ProduceID'];
    expect(a, startsWith('zwjsg-'));
    expect(a, isNot(b));
  });

  testWidgets('加了标识的 PNG 还能正常打开', (tester) async {
    final labeled = AigcLabel.embed(onePixelPng, producer: '再玩我是狗');
    final size = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(labeled);
      final frame = await codec.getNextFrame();
      return Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    });
    expect(size, const Size(1, 1));
  });

  testWidgets('显式标识写的是“AI生成”', (tester) async {
    await tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: Center(child: AiTag(fontSize: 16))));
    expect(find.text('AI生成'), findsOneWidget);
  });
}
