import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zwjsg_app/features/me/cartoon_lab_page.dart';

/// 1x1 的 PNG，充当原生层返回的结果图
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

/// 原生层 runSample / runLibrary 返回的结果
Map<String, Object?> nativeResult() => {
      'aligned': _png,
      'cartoon': _png,
      'cartoonRgba': Uint8List(288 * 288 * 4),
      'mask': Uint8List(288 * 288),
      'size': 288,
      'faces': 2,
      'photoSize': '512x512',
      'noseOffsetPx': 5.4,
      'maxOffsetPx': 6.6,
      'decodeMs': 3.2,
      'visionMs': 41.6,
      'alignMs': 1.1,
      'loadMs': 820.4,
      'modelMs': 35.5,
      'outputMs': 4.0,
      'segmentMs': 60.2,
      'totalMs': 965.9,
    };

void main() {
  const channel = MethodChannel('zwjsg/cartoon_lab');

  Future<List<MethodCall>> pumpPage(
    WidgetTester tester,
    Future<Object?> Function(MethodCall call) handler, {
    required StickerRenderer renderSticker,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(home: CartoonLabPage(renderSticker: renderSticker)));
    return calls;
  }

  testWidgets('卡通化验证页：用样图试，显示耗时，贴纸画好前先提示', (tester) async {
    final pending = Completer<ui.Image>();
    final calls = await pumpPage(tester, (call) async => nativeResult(), renderSticker: (_) => pending.future);

    expect(find.text('先用样图试一下，再换自己的照片'), findsOneWidget);
    await tester.tap(find.text('用样图试'));
    await tester.pumpAndSettle();

    expect(calls.single.method, 'runSample');
    expect(find.text('正在画平涂墨线贴纸…'), findsOneWidget);
    expect(find.text('512x512'), findsOneWidget);
    expect(find.text('2 张，用了最大的那张'), findsOneWidget);
    expect(find.text('5 像素'), findsOneWidget);
    expect(find.text('7 像素'), findsOneWidget);
    expect(find.text('820 ms'), findsOneWidget);
    expect(find.text('60 ms'), findsOneWidget);
    expect(find.text('966 ms'), findsOneWidget);
  });

  testWidgets('卡通化验证页：贴纸画好后并排显示“人”和“变狗”', (tester) async {
    final sticker = await tester.runAsync(
      () => PhotoSticker.toImage(Uint8List(PhotoSticker.canvasSize * PhotoSticker.canvasSize * 4)),
    );
    await pumpPage(tester, (call) async => nativeResult(), renderSticker: (_) async => sticker!.clone());

    await tester.tap(find.text('用样图试'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('照片卡通形象，变狗阶段 0'), findsOneWidget);
    expect(find.bySemanticsLabel('照片卡通形象，变狗阶段 2'), findsOneWidget);
    expect(find.text('变狗（阶段 2）'), findsOneWidget);
    expect(find.textContaining('平涂墨线贴纸（Flutter）'), findsOneWidget);
    sticker!.dispose();
  });

  testWidgets('卡通化验证页：找不到脸、抠不出人像时说原因，没选照片时什么都不变', (tester) async {
    var failFace = true;
    await pumpPage(
      tester,
      (call) async {
        if (call.method == 'runSample') {
          if (failFace) throw PlatformException(code: 'lab_failed', message: '没找到人脸，换一张正脸、光线亮一点的照片');
          return nativeResult();
        }
        return null; // 打开相册后没选就关了
      },
      renderSticker: (_) async => throw StateError('没抠出人像'),
    );

    await tester.tap(find.text('用样图试'));
    await tester.pumpAndSettle();
    expect(find.text('没找到人脸，换一张正脸、光线亮一点的照片'), findsOneWidget);

    await tester.tap(find.text('从相册选一张'));
    await tester.pumpAndSettle();
    expect(find.text('先用样图试一下，再换自己的照片'), findsOneWidget);

    failFace = false;
    await tester.tap(find.text('用样图试'));
    await tester.pumpAndSettle();
    expect(find.text('贴纸没画出来：没抠出人像'), findsOneWidget);
  });
}
