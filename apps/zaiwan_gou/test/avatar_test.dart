import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:series_share/series_share.dart';
import 'package:zwjsg_app/core/api_client.dart';
import 'package:zwjsg_app/core/app_state.dart';
import 'package:zwjsg_app/core/usage_channel.dart';


import 'package:zwjsg_app/core/cartoonizer.dart';
import 'package:zwjsg_app/core/groups.dart';
import 'package:zwjsg_app/features/card/card_page.dart';
import 'package:zwjsg_app/features/me/me_page.dart';
import 'package:zwjsg_app/features/group/member_avatar.dart';
import 'package:zwjsg_app/features/onboarding/avatar_page.dart';
import 'package:zwjsg_app/widgets/my_avatar.dart';

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

  /// 上传形象、改设置按先后记下来
  final calls = <String>[];

  @override
  Future<Map<String, dynamic>> uploadAvatar(Uint8List png) async {
    final e = uploadError;
    if (e != null) throw e;
    uploads.add(png);
    calls.add('upload');
    return {'avatar_regen_left': 2};
  }

  @override
  Future<Uint8List> downloadAvatar(String url) async {
    downloads.add(url);
    return remoteAvatar!;
  }

  int exports = 0;
  ApiException? exportError;

  @override
  Future<({String code, DateTime expiresAt})> exportAvatar() async {
    final e = exportError;
    if (e != null) throw e;
    exports++;
    return (code: 'ABCDEFGH', expiresAt: DateTime.now().add(const Duration(minutes: 10)));
  }

  @override
  Future<Map<String, dynamic>> me() async => meData;

  @override
  Future<String> smsLogin(String phone, String code) async => 'token';

  @override
  Future<void> logout() async {}

  /// 传给服务端的设置，按顺序
  final settings = <Map<String, dynamic>>[];

  @override
  Future<void> updateSettings(Map<String, dynamic> settings) async {
    this.settings.add(settings);
    calls.add('settings');
  }
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

/// 点照片那一格（还没有照片形象），第一次会先问同意；再选拍照还是从相册选
Future<void> pickPhoto(WidgetTester tester, String source, {String from = '用照片做形象'}) async {
  if (from == '换一张照片') {
    await tester.tap(find.text(from));
  } else {
    await tester.tap(find.bySemanticsLabel(from));
  }
  await tester.pumpAndSettle();
  if (find.text('同意，开始').evaluate().isNotEmpty) {
    await tester.tap(find.text('同意，开始'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(source));
  await tester.pumpAndSettle();
}

/// 大图（形象页上面那张）画的是哪张预设形象；是拍照形象时为 null
AvatarPreset? previewPreset(WidgetTester tester) {
  final big = find.byWidgetPredicate((w) => w is DogAvatar && w.size == 196);
  return big.evaluate().isEmpty ? null : tester.widget<DogAvatar>(big).preset;
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
      expect(find.text('先挑一个你'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('用照片做形象'));
      await tester.pumpAndSettle();
      expect(find.text('用照片做形象之前'), findsOneWidget);
      expect(find.textContaining('不保存、不上传'), findsWidgets);
      expect(find.textContaining('晒出去的结算卡会标上“AI生成”'), findsOneWidget);
      await tester.tap(find.text('先不用了'));
      await tester.pumpAndSettle();
      expect(cartoonizer.calls, isEmpty);
      expect(state.faceConsented, isFalse);
      expect(find.text('拍一张自拍'), findsNothing);

      await pickPhoto(tester, '拍一张自拍');
      expect(state.faceConsented, isTrue);
      expect(cartoonizer.calls, [PhotoSource.camera]);
      expect(find.text('这就是你'), findsOneWidget);
      expect(find.text('AI生成'), findsOneWidget);
      for (final stage in [0, 1, 2, 3, 4, 5]) {
        expect(find.bySemanticsLabel('照片卡通形象，变狗阶段 $stage'), findsOneWidget, reason: '阶段 $stage');
      }

      // 换一张：从相册选，不再问
      await tester.tap(find.text('换一张照片'));
      await tester.pumpAndSettle();
      expect(find.text('用照片做形象之前'), findsNothing);
      await tester.tap(find.text('从相册选一张'));
      await tester.pumpAndSettle();
      expect(cartoonizer.calls, [PhotoSource.camera, PhotoSource.library]);
      sticker.dispose();
    });

    testWidgets('没拍就关了什么都不变；找不到脸时说原因；多张脸时说用了哪张', (tester) async {
      final sticker = await whiteSticker(tester);
      final cartoonizer = FakeCartoonizer()..next = null;
      final state = await newState(tester, prefs: {'face_consent_version': AppState.faceConsentVersion});
      await pumpAvatarPage(tester, state, cartoonizer: cartoonizer, sticker: sticker);

      await pickPhoto(tester, '拍一张自拍');
      expect(find.text('先挑一个你'), findsOneWidget);
      expect(previewPreset(tester), AvatarPreset.ahoge);

      cartoonizer.next = PlatformException(code: 'lab_failed', message: '没找到人脸，换一张正脸、光线亮一点的照片');
      await pickPhoto(tester, '从相册选一张');
      expect(find.text('没找到人脸，换一张正脸、光线亮一点的照片'), findsOneWidget);
      expect(find.text('先挑一个你'), findsOneWidget);

      cartoonizer.next = face(faces: 3);
      await pickPhoto(tester, '从相册选一张');
      expect(find.text('照片里有 3 张脸，用了最大的那张'), findsOneWidget);
      expect(previewPreset(tester), isNull);
      sticker.dispose();
    });

    testWidgets('就用这个：没登录时存在手机上、等登录后再传，接着去设目标', (tester) async {
      final sticker = await whiteSticker(tester);
      final api = FakeApi();
      final store = MemoryAvatarStore();
      final state = await newState(tester,
          prefs: {'face_consent_version': AppState.faceConsentVersion}, api: api, store: store);
      await pumpAvatarPage(tester, state, cartoonizer: FakeCartoonizer(), sticker: sticker);

      await pickPhoto(tester, '拍一张自拍');
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
      await pickPhoto(tester, '拍一张自拍');
      await confirm(tester, () => false);
      expect(find.text('重新生成次数用完了'), findsOneWidget);
      expect(store.png, isNull);
      expect(state.photoAvatar, isNull);
      expect(find.text('这就是你'), findsOneWidget);
      // 等提示自己消失（它盖在按钮上）
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

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
      // 用着拍照形象：先选中它
      expect(find.bySemanticsLabel('照片卡通形象，变狗阶段 0'), findsOneWidget);
      expect(previewPreset(tester), isNull);
      expect(find.text('换形象的次数用完了'), findsOneWidget);
      await tester.tap(find.text('换一张照片'));
      await tester.pumpAndSettle();
      expect(find.text('拍一张自拍'), findsNothing);
      expect(find.text('这就是你'), findsNothing);
      // 换成预设形象不算次数
      await tester.tap(find.bySemanticsLabel('形象：寸头'));
      await tester.pumpAndSettle();
      expect(find.text('换形象的次数用完了'), findsNothing);
      await confirm(tester, () => state.usesPreset);
      expect(state.avatarPreset, AvatarPreset.buzz);
      expect(find.text('去换形象'), findsOneWidget);
      sticker.dispose();
    });

    testWidgets('做不了拍照形象的手机：只能挑预设形象', (tester) async {
      final sticker = await whiteSticker(tester);
      final state = await newState(tester);
      await pumpAvatarPage(tester, state, cartoonizer: FakeCartoonizer(isSupported: false), sticker: sticker);

      expect(find.bySemanticsLabel('用照片做形象'), findsNothing);
      expect(find.textContaining('这台手机做不了拍照形象'), findsOneWidget);
      for (final p in AvatarPreset.values) {
        expect(find.bySemanticsLabel('形象：${p.label}'), findsOneWidget);
      }
      await confirm(tester, () => state.usesPreset);
      expect(state.avatarPreset, AvatarPreset.ahoge);
      expect(find.text('设目标页'), findsOneWidget);
      sticker.dispose();
    });

    testWidgets('“我的”页能进去换形象', (tester) async {
      await pumpApp(tester, {'onboarded': true});
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('呆毛  ›'), findsOneWidget);
      await tester.tap(find.text('换个形象'));
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

  group('导出到“什么鬼天气”', () {
    Future<AppState> pumpMe(WidgetTester tester, {bool loggedIn = true, bool photo = true, FakeApi? api, bool pending = false}) async {
      final store = MemoryAvatarStore();
      if (photo) {
        final sticker = await whiteSticker(tester);
        store.png = await stickerPng(tester, sticker);
        sticker.dispose();
      }
      final state = await newState(tester,
          prefs: {if (loggedIn) 'token': 't', if (pending) 'avatar_pending_upload': true}, api: api, store: store);
      await tester.runAsync(state.loadAvatar);
      usePhoneScreen(tester);
      final router = GoRouter(initialLocation: '/me', routes: [
        GoRoute(path: '/me', builder: (_, __) => const MePage()),
        GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('登录页'))),
      ]);
      await tester.pumpWidget(AppScope(state: state, child: MaterialApp.router(theme: Pop.theme(), routerConfig: router)));
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('有拍照形象才能导出', (tester) async {
      await pumpMe(tester, photo: false);
      expect(find.text('导出到「什么鬼天气」'), findsNothing);
    });

    testWidgets('没登录时先去登录', (tester) async {
      final api = FakeApi();
      await pumpMe(tester, loggedIn: false, api: api);
      await tester.tap(find.text('导出到「什么鬼天气」'));
      await tester.pumpAndSettle();
      expect(find.text('导出要先登录'), findsOneWidget);
      await tester.tap(find.text('去登录'));
      await tester.pumpAndSettle();
      expect(find.text('登录页'), findsOneWidget);
      expect(api.exports, 0);
    });

    testWidgets('生成导出码，分成两段显示，能复制', (tester) async {
      final api = FakeApi();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await pumpMe(tester, api: api);
      await tester.tap(find.text('导出到「什么鬼天气」'));
      await tester.pumpAndSettle();
      expect(api.exports, 1);
      expect(find.text('ABCD-EFGH'), findsOneWidget);
      expect(find.textContaining('只能用一次'), findsOneWidget);

      await tester.tap(find.text('复制导出码'));
      await tester.pumpAndSettle();
      expect(copied, 'ABCDEFGH');
      expect(find.text('复制好了'), findsOneWidget);
    });

    testWidgets('形象还没传上去的先补传再导出；出错时说原因', (tester) async {
      final api = FakeApi();
      final state = await pumpMe(tester, api: api, pending: true);
      await tester.runAsync(state.exportAvatar);
      expect(api.uploads, hasLength(1));
      expect(api.exports, 1);

      api.exportError = ApiException('还没有拍照形象，先在“我的 › 形象”里做一个', statusCode: 422);
      await tester.tap(find.text('导出到「什么鬼天气」'));
      await tester.pumpAndSettle();
      expect(find.text('还没有拍照形象，先在“我的 › 形象”里做一个'), findsOneWidget);
    });
  });

  // 隐式标识本身的格式在 packages/series_share 的测试里
  group('AI 标识', () {
    Future<PngExporter> pumpCard(WidgetTester tester, {required bool photo, AvatarPreset? preset}) async {
      usePhoneScreen(tester);
      final sticker = await whiteSticker(tester);
      final store = MemoryAvatarStore()..png = photo ? await stickerPng(tester, sticker) : null;
      final state = await newState(tester, store: store)
        ..debugSetUsage(const UsageSnapshot(totalMinutes: 130, pickups: 0, lateNightMinutes: 0, categoryMinutes: {}));
      await tester.runAsync(state.loadAvatar);
      if (preset != null) await tester.runAsync(() => state.setAvatarPreset(preset));
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
      expect(AigcLabel.read(exporter.saved.single)?['ContentProducer'], '再玩我是狗');
    });

    testWidgets('默认形象（代码画的）不是 AI 生成的，不加标识', (tester) async {
      final exporter = await pumpCard(tester, photo: false);
      expect(find.text('AI生成'), findsNothing);
      await tester.tap(find.text('保存图片'));
      await tester.pumpAndSettle();
      expect(AigcLabel.read(exporter.saved.single), isNull);
    });

    testWidgets('有拍照形象但换成了预设形象：画的是预设形象，不加标识', (tester) async {
      final exporter = await pumpCard(tester, photo: true, preset: AvatarPreset.parted);
      expect(find.text('AI生成'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('照片卡通形象')), findsNothing);
      await tester.tap(find.text('保存图片'));
      await tester.pumpAndSettle();
      expect(AigcLabel.read(exporter.saved.single), isNull);
    });
  });

  group('预设形象', () {
    test('预设形象的名字和狗后端 config/dog.php 的 avatar_presets 一致（顺序也一样）', () {
      final php = File('../../backends/zaiwan_gou_api/config/dog.php').readAsStringSync();
      final list = RegExp(r"'avatar_presets' => \[([^\]]*)\]").firstMatch(php)!.group(1)!;
      expect([for (final m in RegExp(r"'([a-z_]+)'").allMatches(list)) m.group(1)],
          [for (final p in AvatarPreset.values) p.name]);
      expect(AvatarPreset.values.map((p) => p.label).toSet(), hasLength(AvatarPreset.values.length));
    });

    testWidgets('挑一张：默认选中呆毛，点哪张大图换哪张；就用这个才记下来，没登录时等登录后再告诉服务端', (tester) async {
      final sticker = await whiteSticker(tester);
      final api = FakeApi();
      final state = await newState(tester, api: api);
      await pumpAvatarPage(tester, state, cartoonizer: FakeCartoonizer(), sticker: sticker);
      expect(previewPreset(tester), AvatarPreset.ahoge);
      expect(tester.getSemantics(find.bySemanticsLabel('形象：呆毛')), containsSemantics(isSelected: true));

      await tester.tap(find.bySemanticsLabel('形象：卷毛'));
      await tester.pumpAndSettle();
      expect(previewPreset(tester), AvatarPreset.curly);
      expect(tester.getSemantics(find.bySemanticsLabel('形象：卷毛')), containsSemantics(isSelected: true));
      expect(tester.getSemantics(find.bySemanticsLabel('形象：呆毛')), containsSemantics(isSelected: false));
      // 下面一排刷多了的样子也是卷毛
      expect(
        [for (final a in tester.widgetList<DogAvatar>(find.byType(DogAvatar))) if (a.size == 50) (a.stage, a.preset)],
        [for (var s = 1; s <= 5; s++) (s, AvatarPreset.curly)],
      );
      expect(state.usesPreset, isFalse, reason: '点“就用这个”之前不算');

      await confirm(tester, () => state.usesPreset);
      expect(state.avatarPreset, AvatarPreset.curly);
      expect(find.text('设目标页'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('avatar_preset'), 'curly');
      expect(api.settings, isEmpty);

      // 登录后补上：这台手机上新挑的，比服务端记着的新
      api.meData = {'avatar_preset': 'bun'};
      await tester.runAsync(() => state.login('13800000000', '123456'));
      expect(api.settings, [
        {'avatar_preset': 'curly'}
      ]);
      expect(state.avatarPreset, AvatarPreset.curly);
      expect(prefs.getBool('avatar_preset_pending'), isFalse);
      sticker.dispose();
    });

    testWidgets('有拍照形象也能换成预设形象：照片还留着，能换回来，来回换都不用重新上传', (tester) async {
      final sticker = await whiteSticker(tester);
      final png = await stickerPng(tester, sticker);
      final api = FakeApi();
      final store = MemoryAvatarStore()..png = png;
      final state = await newState(tester, prefs: {'token': 't'}, api: api, store: store);
      await tester.runAsync(state.loadAvatar);
      expect(state.photoAvatar, isNotNull);

      await tester.runAsync(() => state.setAvatarPreset(AvatarPreset.bob));
      expect(state.photoAvatar, isNull);
      expect(state.photoAvatarPng, isNull);
      expect(state.savedPhotoAvatar, isNotNull);
      expect(store.png, png, reason: '拍照形象还留在手机上');
      expect(api.settings.last, {'avatar_preset': 'bob'});

      // 各处画的是挑的那张
      await tester.pumpWidget(AppScope(
        state: state,
        child: const Directionality(textDirection: TextDirection.ltr, child: MyAvatar(stage: 2)),
      ));
      expect(tester.widget<DogAvatar>(find.byType(DogAvatar)).preset, AvatarPreset.bob);
      expect(find.byType(PhotoDogAvatar), findsNothing);

      // 形象页：选中的是粉色短发；点照片那一格换回拍照形象
      await pumpAvatarPage(tester, state, cartoonizer: FakeCartoonizer(), sticker: sticker, editing: true);
      expect(previewPreset(tester), AvatarPreset.bob);
      await tester.tap(find.bySemanticsLabel('拍照形象'));
      await tester.pumpAndSettle();
      expect(previewPreset(tester), isNull);
      expect(find.text('AI生成'), findsOneWidget);
      await confirm(tester, () => !state.usesPreset);
      expect(state.photoAvatar, isNotNull);
      expect(api.settings.last, {'avatar_preset': null});
      expect(api.uploads, isEmpty);
      expect(find.text('去换形象'), findsOneWidget);
      sticker.dispose();
    });

    testWidgets('登录时：没挑过的用服务端记着的那张，认不出来的当没挑过；没登录时拍的照片形象传上去，不用服务端记着的', (tester) async {
      var api = FakeApi()..meData = {'avatar_preset': 'bun'};
      var state = await newState(tester, api: api);
      await tester.runAsync(() => state.login('13800000000', '123456'));
      expect(state.avatarPreset, AvatarPreset.bun);
      expect(state.usesPreset, isTrue);
      expect(api.settings, isEmpty);

      // 比如新版本加的预设，旧版本认不出来
      api = FakeApi()..meData = {'avatar_preset': 'mohawk'};
      state = await newState(tester, api: api);
      await tester.runAsync(() => state.login('13800000000', '123456'));
      expect(state.usesPreset, isFalse);
      expect(state.avatarPreset, AvatarPreset.ahoge);

      final sticker = await whiteSticker(tester);
      final png = await stickerPng(tester, sticker);
      api = FakeApi()..meData = {'avatar_preset': 'bun'};
      final store = MemoryAvatarStore()..png = png;
      state = await newState(tester, prefs: {'avatar_pending_upload': true}, api: api, store: store);
      await tester.runAsync(state.loadAvatar);
      await tester.runAsync(() => state.login('13800000000', '123456'));
      expect(api.uploads, [png]);
      expect(state.usesPreset, isFalse);
      expect(state.photoAvatar, isNotNull);
      sticker.dispose();
    });

    testWidgets('打开 App 时补上没告诉服务端的：先传拍照形象，再说换了哪张脸', (tester) async {
      final sticker = await whiteSticker(tester);
      final png = await stickerPng(tester, sticker);
      final api = FakeApi();
      final state = await newState(tester,
          prefs: {'token': 't', 'avatar_pending_upload': true, 'avatar_preset': 'buzz', 'avatar_preset_pending': true},
          api: api,
          store: MemoryAvatarStore()..png = png);
      expect(state.avatarPreset, AvatarPreset.buzz);
      await tester.runAsync(() async {
        await state.loadAvatar();
        for (var i = 0; i < 40 && api.calls.length < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(api.calls, ['upload', 'settings']);
      expect(api.settings.single, {'avatar_preset': 'buzz'});
      expect(state.avatarPreset, AvatarPreset.buzz);
      expect(state.photoAvatar, isNull, reason: '用的还是寸头');
      sticker.dispose();
    });

    testWidgets('做了新的拍照形象就不用预设形象了；退出登录后清掉', (tester) async {
      final sticker = await whiteSticker(tester);
      final png = await stickerPng(tester, sticker);
      final state = await newState(tester, prefs: {'token': 't', 'avatar_preset': 'long'});
      expect(state.usesPreset, isTrue);
      await tester.runAsync(() => state.setPhotoAvatar(png));
      expect(state.usesPreset, isFalse);
      expect(state.photoAvatar, isNotNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('avatar_preset'), isNull);

      await tester.runAsync(() => state.setAvatarPreset(AvatarPreset.long));
      await tester.runAsync(state.logout);
      expect(state.usesPreset, isFalse);
      expect(state.avatarPreset, AvatarPreset.ahoge);
      expect(state.savedPhotoAvatar, isNull);
      sticker.dispose();
    });

    testWidgets('“我的”页写着用的是哪张', (tester) async {
      await pumpApp(tester, {'onboarded': true, 'avatar_preset': 'bob'});
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('粉色短发  ›'), findsOneWidget);
    });

    testWidgets('群里：用预设形象的群友画 TA 挑的那张，没挑过是呆毛', (tester) async {
      final m = GroupMember.fromJson({'id': 2, 'nickname': '小王', 'avatar_url': null, 'avatar_preset': 'curly'});
      expect(m.avatarPreset, AvatarPreset.curly);
      expect(GroupMember.fromJson({'id': 3, 'nickname': '小李', 'avatar_preset': 'nope'}).avatarPreset, isNull);
      final king = KingOfDay.fromJson(
          {'user_id': 2, 'nickname': '小王', 'avatar_preset': 'bob', 'date': '2026-11-26', 'dog_percent': 95, 'stage': 3});
      expect(king.avatarPreset, AvatarPreset.bob);

      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [
          MemberBadge(key: const Key('a'), url: null, preset: m.avatarPreset, stage: 3, size: 60),
          const MemberBadge(key: Key('b'), url: null, stage: 1, size: 60),
        ]),
      ));
      DogAvatar dogIn(String key) =>
          tester.widget<DogAvatar>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(DogAvatar)));
      expect((dogIn('a').preset, dogIn('a').stage), (AvatarPreset.curly, 3));
      expect(dogIn('b').preset, AvatarPreset.ahoge);
    });
  });
}
