import 'dart:convert';
import 'dart:ui' as ui;

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zwjsg_app/core/aigc_label.dart';
import 'package:zwjsg_app/core/api_client.dart';
import 'package:zwjsg_app/core/app_state.dart';
import 'package:zwjsg_app/core/avatar_store.dart';
import 'package:zwjsg_app/core/card_exporter.dart';
import 'package:zwjsg_app/core/cartoonizer.dart';
import 'package:zwjsg_app/features/card/card_page.dart';
import 'package:zwjsg_app/features/onboarding/avatar_page.dart';

import 'me_features_test.dart' show FakeReminders;
import 'widget_test.dart' show pumpApp, usePhoneScreen;

/// 1x1 的 PNG
final onePixelPng =
    base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

class MemoryAvatarStore implements AvatarStore {
  Uint8List? png;

  @override
  Future<Uint8List?> load() async => png;

  @override
  Future<void> save(Uint8List value) async => png = value;

  @override
  Future<void> delete() async => png = null;
}

class FakeCartoonizer implements Cartoonizer {
  FakeCartoonizer({this.isSupported = true});

  @override
  final bool isSupported;

  final calls = <PhotoSource>[];

  /// 下一次返回什么：[CartoonFace]、null（用户没拍），或者要抛的异常
  Object? next = face();

  @override
  Future<CartoonFace?> cartoonize(PhotoSource source) async {
    calls.add(source);
    final n = next;
    if (n is Exception) throw n;
    return n as CartoonFace?;
  }
}

CartoonFace face({int faces = 1}) =>
    CartoonFace(rgba: Uint8List(288 * 288 * 4), mask: Uint8List(288 * 288), faces: faces);

/// 服务端：只记下传了什么，不发真的请求
class FakeApi extends ApiClient {
  final uploads = <Uint8List>[];
  ApiException? uploadError;
  Map<String, dynamic> meData = {};
  Uint8List? remoteAvatar;
  final downloads = <String>[];

  @override
  Future<Map<String, dynamic>> uploadAvatar(Uint8List png) async {
    final e = uploadError;
    if (e != null) throw e;
    uploads.add(png);
    return {'avatar_regen_left': 2};
  }

  @override
  Future<Uint8List> downloadAvatar(String url) async {
    downloads.add(url);
    return remoteAvatar!;
  }

  @override
  Future<Map<String, dynamic>> me() async => meData;

  @override
  Future<String> smsLogin(String phone, String code) async => 'token';

  @override
  Future<void> logout() async {}

  @override
  Future<void> updateSettings(Map<String, dynamic> settings) async {}
}

/// 截图返回一张真的 PNG，保存时记下来
class PngExporter implements CardExporter {
  final saved = <Uint8List>[];

  @override
  Future<Uint8List> capture(GlobalKey boundaryKey) async => onePixelPng;

  @override
  Future<void> save(Uint8List png) async => saved.add(png);

  @override
  Future<void> share(Uint8List png, {Rect? origin}) async {}
}

/// 320x320 的白色贴纸
Future<ui.Image> whiteSticker(WidgetTester tester) async => (await tester.runAsync(() {
      final rgba = Uint8List(PhotoSticker.canvasSize * PhotoSticker.canvasSize * 4)..fillRange(0, 320 * 320 * 4, 255);
      return PhotoSticker.toImage(rgba);
    }))!;

/// 贴纸的 PNG，充当存在手机上、服务端上的形象
Future<Uint8List> stickerPng(WidgetTester tester, ui.Image sticker) async => (await tester.runAsync(() async {
      final data = await sticker.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    }))!;

Future<AppState> newState(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  FakeApi? api,
  AvatarStore? store,
}) async {
  SharedPreferences.setMockInitialValues({'privacy_version': AppState.privacyVersion, ...prefs});
  return AppState(
    await SharedPreferences.getInstance(),
    reminders: FakeReminders(),
    api: api ?? FakeApi(),
    avatars: store ?? MemoryAvatarStore(),
  );
}

Future<void> pumpAvatarPage(
  WidgetTester tester,
  AppState state, {
  required FakeCartoonizer cartoonizer,
  required ui.Image sticker,
  bool editing = false,
}) async {
  usePhoneScreen(tester);
  final router = GoRouter(
    initialLocation: editing ? '/me' : '/avatar',
    routes: [
      GoRoute(
        path: '/avatar',
        builder: (_, s) => AvatarPage(
          editing: s.uri.queryParameters['edit'] == '1',
          cartoonizer: cartoonizer,
          renderSticker: (_) async => sticker.clone(),
        ),
      ),
      GoRoute(path: '/goal', builder: (_, __) => const Scaffold(body: Text('设目标页'))),
      GoRoute(
        path: '/me',
        builder: (context, __) => Scaffold(
          body: TextButton(onPressed: () => context.push('/avatar?edit=1'), child: const Text('去换形象')),
        ),
      ),
    ],
  );
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp.router(theme: Pop.theme(), routerConfig: router)));
  await tester.pumpAndSettle();
  if (editing) {
    await tester.tap(find.text('去换形象'));
    await tester.pumpAndSettle();
  }
}

/// “就用这个”要真的编码、解码图片，只能在真实的异步里跑
Future<void> confirm(WidgetTester tester, bool Function() done) async {
  await tester.runAsync(() async {
    await tester.tap(find.text('就用这个'));
    for (var i = 0; i < 40 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  group('形象创建', () {
    testWidgets('第一次用照片前先单独同意；不同意就不打开相机，同意后只问一次', (tester) async {
      final sticker = await whiteSticker(tester);
      final cartoonizer = FakeCartoonizer();
      final state = await newState(tester);
      await pumpAvatarPage(tester, state, cartoonizer: cartoonizer, sticker: sticker);
      expect(find.text('先做一个你'), findsOneWidget);

      await tester.tap(find.text('拍一张自拍'));
      await tester.pumpAndSettle();
      expect(find.text('用照片做形象之前'), findsOneWidget);
      expect(find.textContaining('不保存、不上传'), findsWidgets);
      expect(find.textContaining('晒出去的结算卡会标上“AI生成”'), findsOneWidget);
      await tester.tap(find.text('先不用了'));
      await tester.pumpAndSettle();
      expect(cartoonizer.calls, isEmpty);
      expect(state.faceConsented, isFalse);

      await tester.tap(find.text('拍一张自拍'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('同意，开始'));
      await tester.pumpAndSettle();
      expect(state.faceConsented, isTrue);
      expect(cartoonizer.calls, [PhotoSource.camera]);
      expect(find.text('这就是你'), findsOneWidget);
      expect(find.text('AI生成'), findsOneWidget);
      for (final stage in [0, 1, 2, 3, 4, 5]) {
        expect(find.bySemanticsLabel('照片卡通形象，变狗阶段 $stage'), findsOneWidget, reason: '阶段 $stage');
      }

      // 换一张：从相册选，不再问
      await tester.tap(find.text('换一张'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从相册选一张'));
      await tester.pumpAndSettle();
      expect(find.text('用照片做形象之前'), findsNothing);
      expect(cartoonizer.calls, [PhotoSource.camera, PhotoSource.library]);
      sticker.dispose();
    });

    testWidgets('没拍就关了什么都不变；找不到脸时说原因；多张脸时说用了哪张', (tester) async {
      final sticker = await whiteSticker(tester);
      final cartoonizer = FakeCartoonizer()..next = null;
      final state = await newState(tester, prefs: {'face_consent_version': AppState.faceConsentVersion});
      await pumpAvatarPage(tester, state, cartoonizer: cartoonizer, sticker: sticker);

      await tester.tap(find.text('拍一张自拍'));
      await tester.pumpAndSettle();
      expect(find.text('先做一个你'), findsOneWidget);

      cartoonizer.next = PlatformException(code: 'lab_failed', message: '没找到人脸，换一张正脸、光线亮一点的照片');
      await tester.tap(find.text('从相册选一张'));
      await tester.pumpAndSettle();
      expect(find.text('没找到人脸，换一张正脸、光线亮一点的照片'), findsOneWidget);
      expect(find.text('先做一个你'), findsOneWidget);

      cartoonizer.next = face(faces: 3);
      await tester.tap(find.text('从相册选一张'));
      await tester.pumpAndSettle();
      expect(find.text('照片里有 3 张脸，用了最大的那张'), findsOneWidget);
      sticker.dispose();
    });

    testWidgets('就用这个：没登录时存在手机上、等登录后再传，接着去设目标', (tester) async {
      final sticker = await whiteSticker(tester);
      final api = FakeApi();
      final store = MemoryAvatarStore();
      final state = await newState(tester,
          prefs: {'face_consent_version': AppState.faceConsentVersion}, api: api, store: store);
      await pumpAvatarPage(tester, state, cartoonizer: FakeCartoonizer(), sticker: sticker);

      await tester.tap(find.text('拍一张自拍'));
      await tester.pumpAndSettle();
      await confirm(tester, () => store.png != null);

      expect(store.png, isNotNull);
      expect(state.photoAvatar, isNotNull);
      expect(api.uploads, isEmpty);
      expect(find.text('设目标页'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('avatar_pending_upload'), isTrue);
      sticker.dispose();
    });

    testWidgets('登录了就上传卡通形象；服务端说次数用完时，手机上的形象不变', (tester) async {
      final sticker = await whiteSticker(tester);
      final api = FakeApi();
      final store = MemoryAvatarStore();
      final state = await newState(tester,
          prefs: {'face_consent_version': AppState.faceConsentVersion, 'token': 't'}, api: api, store: store);
      await pumpAvatarPage(tester, state, cartoonizer: FakeCartoonizer(), sticker: sticker);

      api.uploadError = ApiException('重新生成次数用完了', statusCode: 422);
      await tester.tap(find.text('拍一张自拍'));
      await tester.pumpAndSettle();
      await confirm(tester, () => false);
      expect(find.text('重新生成次数用完了'), findsOneWidget);
      expect(store.png, isNull);
      expect(state.photoAvatar, isNull);
      expect(find.text('这就是你'), findsOneWidget);

      api.uploadError = null;
      await confirm(tester, () => store.png != null);
      expect(api.uploads, hasLength(1));
      // 传上去的是贴纸的 PNG
      expect(api.uploads.single.sublist(1, 4), utf8.encode('PNG'));
      expect(state.avatarRegenLeft, 2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('avatar_pending_upload'), isFalse);
      expect(find.text('设目标页'), findsOneWidget);
      sticker.dispose();
    });

    testWidgets('从“我的”换形象：显示还能换几次，次数用完就不能再拍，做完回到上一页', (tester) async {
      final sticker = await whiteSticker(tester);
      final png = await stickerPng(tester, sticker);
      final store = MemoryAvatarStore()..png = png;
      final api = FakeApi()..meData = {'avatar_regen_left': 0};
      final state = await newState(tester,
          prefs: {'face_consent_version': AppState.faceConsentVersion, 'token': 't'}, api: api, store: store);
      await tester.runAsync(state.loadAvatar);
      await tester.runAsync(() => state.login('13800000000', '123456'));
      expect(state.avatarRegenLeft, 0);

      await pumpAvatarPage(tester, state, cartoonizer: FakeCartoonizer(), sticker: sticker, editing: true);
      expect(find.text('换个形象'), findsOneWidget);
      expect(find.bySemanticsLabel('照片卡通形象，变狗阶段 0'), findsOneWidget);
      expect(find.text('换形象的次数用完了'), findsOneWidget);
      await tester.tap(find.text('拍一张自拍'));
      await tester.pumpAndSettle();
      expect(find.text('这就是你'), findsNothing);
      sticker.dispose();
    });

    testWidgets('安卓：拍照形象还在做，先用默认形象', (tester) async {
      final sticker = await whiteSticker(tester);
      final state = await newState(tester);
      await pumpAvatarPage(tester, state, cartoonizer: FakeCartoonizer(isSupported: false), sticker: sticker);

      expect(find.text('拍一张自拍'), findsNothing);
      expect(find.textContaining('安卓版的拍照形象还在做'), findsOneWidget);
      await tester.tap(find.text('先用默认形象'));
      await tester.pumpAndSettle();
      expect(find.text('设目标页'), findsOneWidget);
      sticker.dispose();
    });

    testWidgets('“我的”页能进去换形象', (tester) async {
      await pumpApp(tester, {'onboarded': true});
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('默认形象  ›'), findsOneWidget);
      await tester.tap(find.text('用自拍做形象'));
      await tester.pumpAndSettle();
      expect(find.byType(AvatarPage), findsOneWidget);
      expect(find.text('换个形象'), findsOneWidget);
    });
  });

  group('形象存在手机上', () {
    testWidgets('启动时读出来；退出登录后从手机上删掉，同意过的不用再同意', (tester) async {
      final sticker = await whiteSticker(tester);
      final store = MemoryAvatarStore()..png = await stickerPng(tester, sticker);
      final state = await newState(tester,
          prefs: {'face_consent_version': AppState.faceConsentVersion, 'token': 't'}, store: store);
      await tester.runAsync(state.loadAvatar);
      expect(state.photoAvatar, isNotNull);

      await tester.runAsync(state.logout);
      expect(store.png, isNull);
      expect(state.photoAvatar, isNull);
      expect(state.faceConsented, isTrue);
      expect(state.privacyAccepted, isTrue);
      sticker.dispose();
    });

    testWidgets('图坏了就当没有，用默认形象', (tester) async {
      final store = MemoryAvatarStore()..png = Uint8List.fromList([1, 2, 3]);
      final state = await newState(tester, store: store);
      await tester.runAsync(state.loadAvatar);
      expect(state.photoAvatar, isNull);
    });

    testWidgets('换了手机：登录后把服务端的形象下载回来', (tester) async {
      final sticker = await whiteSticker(tester);
      final api = FakeApi()
        ..meData = {'avatar_url': 'https://cdn.example.com/avatars/1/a.png', 'avatar_regen_left': 3}
        ..remoteAvatar = await stickerPng(tester, sticker);
      final store = MemoryAvatarStore();
      final state = await newState(tester, api: api, store: store);

      await tester.runAsync(() => state.login('13800000000', '123456'));
      expect(api.downloads, ['https://cdn.example.com/avatars/1/a.png']);
      expect(state.photoAvatar, isNotNull);
      expect(store.png, api.remoteAvatar);
      expect(state.avatarRegenLeft, 3);
      sticker.dispose();
    });

    testWidgets('没登录时做的形象，登录后补传', (tester) async {
      final sticker = await whiteSticker(tester);
      final png = await stickerPng(tester, sticker);
      final api = FakeApi();
      final store = MemoryAvatarStore()..png = png;
      final state = await newState(tester, prefs: {'avatar_pending_upload': true}, api: api, store: store);
      await tester.runAsync(state.loadAvatar);
      expect(api.uploads, isEmpty);

      await tester.runAsync(() => state.login('13800000000', '123456'));
      expect(api.uploads, [png]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('avatar_pending_upload'), isFalse);
      sticker.dispose();
    });
  });

  group('AI 标识', () {
    test('导出的 PNG 里写上 AIGC 隐式标识，图本身不变；不是 PNG 时原样返回', () {
      final labeled = AigcLabel.embed(onePixelPng, produceId: 'zwjsg-1');
      expect(AigcLabel.read(labeled), {
        'Label': '1',
        'ContentProducer': '再玩我是狗',
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
      expect(AigcLabel.embed(junk), same(junk));
    });

    testWidgets('加了标识的 PNG 还能正常打开', (tester) async {
      final labeled = AigcLabel.embed(onePixelPng);
      final size = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(labeled);
        final frame = await codec.getNextFrame();
        return Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      });
      expect(size, const Size(1, 1));
    });

    Future<PngExporter> pumpCard(WidgetTester tester, {required bool photo}) async {
      usePhoneScreen(tester);
      final sticker = await whiteSticker(tester);
      final store = MemoryAvatarStore()..png = photo ? await stickerPng(tester, sticker) : null;
      final state = await newState(tester, store: store);
      await tester.runAsync(state.loadAvatar);
      final exporter = PngExporter();
      await tester.pumpWidget(AppScope(state: state, child: MaterialApp(home: CardPage(exporter: exporter))));
      await tester.pumpAndSettle();
      sticker.dispose();
      return exporter;
    }

    testWidgets('拍照形象的结算卡：右下角标“AI生成”，存下来的图片带隐式标识', (tester) async {
      final exporter = await pumpCard(tester, photo: true);
      expect(find.text('AI生成'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('照片卡通形象')), findsOneWidget);
      // 文字高度不低于卡片宽的 5%
      final cardWidth = tester.getSize(find.byType(AspectRatio).first).width;
      final tagText = tester.widget<Text>(find.text('AI生成'));
      expect(tagText.style!.fontSize! >= cardWidth * 0.05, isTrue, reason: '卡片宽 $cardWidth');

      await tester.tap(find.text('保存图片'));
      await tester.pumpAndSettle();
      expect(AigcLabel.read(exporter.saved.single)?['Label'], '1');
    });

    testWidgets('默认形象（代码画的）不是 AI 生成的，不加标识', (tester) async {
      final exporter = await pumpCard(tester, photo: false);
      expect(find.text('AI生成'), findsNothing);
      await tester.tap(find.text('保存图片'));
      await tester.pumpAndSettle();
      expect(AigcLabel.read(exporter.saved.single), isNull);
    });
  });
}
