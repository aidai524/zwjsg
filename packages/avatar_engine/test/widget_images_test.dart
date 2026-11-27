import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一张 320x320 的白色方块，当作照片贴纸
Future<ui.Image> whiteSticker() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 320, 320), Paint()..color = Colors.white);
  return recorder.endRecording().toImage(320, 320);
}

Future<Uint8List> rgba(ui.Image image) async => (await image.toByteData())!.buffer.asUint8List();

Directory tempDir() {
  final dir = Directory.systemTemp.createTempSync('widget_images_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

void main() {
  testWidgets('变狗形象不经过 Widget 树也能画成图片：每个阶段都不一样，照片形象也能画', (tester) async {
    final result = await tester.runAsync(() async {
      final sticker = await whiteSticker();
      final defaults = <Uint8List>[];
      final photos = <Uint8List>[];
      final sizes = <(int, int)>{};
      for (var stage = 0; stage <= 5; stage++) {
        for (final (list, image) in [
          (defaults, await renderDogAvatar(stage: stage, pixels: 180)),
          (photos, await renderPhotoDogAvatar(sticker: sticker, stage: stage, pixels: 180)),
        ]) {
          sizes.add((image.width, image.height));
          list.add(await rgba(image));
          image.dispose();
        }
      }
      sticker.dispose();
      return (defaults, photos, sizes);
    });
    final (defaults, photos, sizes) = result!;
    expect(sizes, {(180, 180)});
    // 每个阶段画出来都不一样（耳朵、鼻子、狗毛……一层层叠上去）
    for (final list in [defaults, photos]) {
      for (var a = 0; a < list.length; a++) {
        for (var b = a + 1; b < list.length; b++) {
          expect(listEquals(list[a], list[b]), isFalse, reason: '阶段 $a 和 $b');
        }
      }
    }
    // 超出 0–5 的阶段按两头算
    final clamped = await tester.runAsync(() async {
      final a = await renderDogAvatar(stage: 9, pixels: 60);
      final b = await renderDogAvatar(stage: 5, pixels: 60);
      final same = listEquals(await rgba(a), await rgba(b));
      a.dispose();
      b.dispose();
      return same;
    });
    expect(clamped, isTrue);
  });

  testWidgets('进化形态只在做人（阶段 0）时画：四种都不一样；变狗了穿不穿都一样；照片形象也一样', (tester) async {
    final result = await tester.runAsync(() async {
      final sticker = await whiteSticker();
      Future<Uint8List> draw(int stage, Evolution? e, {bool photo = false}) async {
        final image = photo
            ? await renderPhotoDogAvatar(sticker: sticker, stage: stage, pixels: 120, evolution: e)
            : await renderDogAvatar(stage: stage, pixels: 120, evolution: e);
        final bytes = await rgba(image);
        image.dispose();
        return bytes;
      }

      final out = <String, Uint8List>{};
      for (final photo in [false, true]) {
        final kind = photo ? 'photo' : 'default';
        out['$kind:plain'] = await draw(0, null, photo: photo);
        for (final e in Evolution.values) {
          out['$kind:${e.name}'] = await draw(0, e, photo: photo);
          out['$kind:dog:${e.name}'] = await draw(2, e, photo: photo);
        }
        out['$kind:dog'] = await draw(2, null, photo: photo);
      }
      sticker.dispose();
      return out;
    });
    final images = result!;
    for (final kind in ['default', 'photo']) {
      final looks = [images['$kind:plain']!, for (final e in Evolution.values) images['$kind:${e.name}']!];
      for (var a = 0; a < looks.length; a++) {
        for (var b = a + 1; b < looks.length; b++) {
          expect(listEquals(looks[a], looks[b]), isFalse, reason: '$kind 第 $a 和第 $b 种');
        }
      }
      for (final e in Evolution.values) {
        expect(listEquals(images['$kind:dog:${e.name}'], images['$kind:dog']), isTrue, reason: '$kind ${e.name} 变狗以后');
      }
    }
    expect(Evolution.byName('elite'), Evolution.elite);
    expect(Evolution.byName('nope'), isNull);
    expect(Evolution.byName(null), isNull);
  });

  testWidgets('形象图画进目录、记下签名；签名没变不重画，缺图、换签名才重画', (tester) async {
    final dir = tempDir();
    var renders = 0;
    Map<String, Future<ui.Image> Function()> images() => {
          for (var stage = 0; stage <= 5; stage++)
            'dog_$stage.png': () {
              renders++;
              return renderDogAvatar(stage: stage, pixels: 60);
            },
        };

    Future<bool> sync(String signature, {bool Function()? stale}) async =>
        (await tester.runAsync(() => WidgetImages.sync(dir: dir.path, signature: signature, images: images(), stale: stale)))!;

    expect(await sync('v1:default'), isTrue);
    expect(renders, 6);
    expect(File('${dir.path}/${WidgetImages.versionFile}').readAsStringSync(), 'v1:default');
    expect(dir.listSync().map((f) => f.uri.pathSegments.last).where((n) => n.endsWith('.tmp')), isEmpty);

    expect(await sync('v1:default'), isFalse);
    expect(renders, 6);

    File('${dir.path}/dog_3.png').deleteSync();
    expect(await sync('v1:default'), isTrue);
    expect(renders, 12);

    expect(await sync('v2:default'), isTrue);
    expect(renders, 18);

    // 画到一半形象又换了：停下，不写签名，下次重画
    var calls = 0;
    expect(await sync('v3:photo', stale: () => ++calls > 2), isFalse);
    expect(renders, 20);
    expect(File('${dir.path}/${WidgetImages.versionFile}').readAsStringSync(), 'v2:default');
  });

  test('原图指纹：同样的图一样，不同的图不一样', () {
    final a = Uint8List.fromList([1, 2, 3]);
    expect(WidgetImages.fingerprint(a), WidgetImages.fingerprint(Uint8List.fromList([1, 2, 3])));
    expect(WidgetImages.fingerprint(a), isNot(WidgetImages.fingerprint(Uint8List.fromList([1, 2, 4]))));
    expect(WidgetImages.fingerprint(a), startsWith('3-'));
  });
}
