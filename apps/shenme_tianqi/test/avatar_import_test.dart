import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pop_ui/pop_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shenme_tianqi/core/api_client.dart';
import 'package:shenme_tianqi/core/app_state.dart';
import 'package:shenme_tianqi/core/models.dart';
import 'package:shenme_tianqi/features/settings/import_avatar_sheet.dart';
import 'package:shenme_tianqi/features/settings/settings_page.dart';
import 'package:shenme_tianqi/widgets/weather_avatars.dart';

class MemoryAvatarStore implements AvatarStore {
  Uint8List? png;

  @override
  Future<Uint8List?> load() async => png;

  @override
  Future<void> save(Uint8List value) async => png = value;

  @override
  Future<void> delete() async => png = null;
}

/// 服务端：导入时返回 [importPng]，上传、删除、下载都只记下来
class AvatarApi extends WeatherApi {
  Uint8List? importPng;
  ApiException? importError;
  final imports = <String>[];
  final uploads = <Uint8List>[];
  int deletes = 0;
  Map<String, dynamic> meData = {};
  final remote = <String, Uint8List>{};
  final downloads = <String>[];

  @override
  Future<Uint8List> importAvatar(String code) async {
    imports.add(code);
    final e = importError;
    if (e != null) throw e;
    return importPng!;
  }

  @override
  Future<Map<String, dynamic>> uploadAvatar(Uint8List png) async {
    uploads.add(png);
    return const {};
  }

  @override
  Future<void> deleteAvatar() async => deletes++;

  @override
  Future<Uint8List> downloadAvatar(String url) async {
    downloads.add(url);
    final png = remote[url];
    if (png == null) throw ApiException('下载不到');
    return png;
  }

  @override
  Future<Map<String, dynamic>> me() async => meData;

  @override
  Future<String> smsLogin(String phone, String code) async => 'token';

  @override
  Future<void> logout() async {}

  @override
  Future<void> updateSettings(Map<String, dynamic> settings) async {}

  @override
  Future<List<City>> cities() async => const [];
}

/// 320x320 白色贴纸的 PNG，充当从狗 App 导进来的形象
Future<Uint8List> stickerPng(WidgetTester tester) async => (await tester.runAsync(() async {
      final rgba = Uint8List(PhotoSticker.canvasSize * PhotoSticker.canvasSize * 4)..fillRange(0, 320 * 320 * 4, 255);
      final image = await PhotoSticker.toImage(rgba);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;

Future<AppState> newState({Map<String, Object> prefs = const {}, AvatarApi? api, AvatarStore? store}) async {
  SharedPreferences.setMockInitialValues({'privacy_version': AppState.privacyVersion, 'onboarded': true, ...prefs});
  return AppState(await SharedPreferences.getInstance(), api: api ?? AvatarApi(), avatars: store ?? MemoryAvatarStore());
}

Future<void> pumpSettings(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp(theme: Pop.theme(), home: const SettingsPage())));
  await tester.pumpAndSettle();
}

/// 导入要真的解码图片，只能在真实的异步里等它做完
Future<void> tapAndWait(WidgetTester tester, Finder button, bool Function() done) async {
  await tester.runAsync(() async {
    await tester.tap(button);
    for (var i = 0; i < 40 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  group('导入形象', () {
    testWidgets('没登录也能导入：先存在手机上，登录后再传服务端', (tester) async {
      final png = await stickerPng(tester);
      final api = AvatarApi()..importPng = png;
      final store = MemoryAvatarStore();
      final state = await newState(api: api, store: store);

      await tester.runAsync(() => state.importAvatar('abcd-efgh'));
      expect(api.imports, ['abcd-efgh']);
      expect(state.avatar, isNotNull);
      expect(store.png, png);
      expect(api.uploads, isEmpty);

      await tester.runAsync(() => state.login('13800000000', '123456'));
      expect(api.uploads, [png]);
      expect((await SharedPreferences.getInstance()).getBool('avatar_pending_upload'), isFalse);
    });

    testWidgets('登录了导入就直接传服务端', (tester) async {
      final png = await stickerPng(tester);
      final api = AvatarApi()..importPng = png;
      final state = await newState(prefs: {'token': 't'}, api: api);

      await tester.runAsync(() => state.importAvatar('ABCDEFGH'));
      expect(api.uploads, [png]);
    });

    testWidgets('码不对时抛出给用户看的话，原来的形象不变', (tester) async {
      final api = AvatarApi()..importError = ApiException('导出码不对或已经过期', statusCode: 422);
      final state = await newState(api: api);

      Object? error;
      await tester.runAsync(() async {
        try {
          await state.importAvatar('ABCDEFGH');
        } catch (e) {
          error = e;
        }
      });
      expect(error, isA<ApiException>());
      expect(state.avatar, isNull);
    });

    testWidgets('换了手机：登录后把服务端的形象下载回来', (tester) async {
      final png = await stickerPng(tester);
      const url = 'https://cdn.example.com/avatars/1/a.png';
      final api = AvatarApi()
        ..meData = {'avatar_url': url}
        ..remote[url] = png;
      final store = MemoryAvatarStore();
      final state = await newState(api: api, store: store);

      await tester.runAsync(() => state.login('13800000000', '123456'));
      expect(api.downloads, [url]);
      expect(state.avatar, isNotNull);
      expect(store.png, png);
    });

    testWidgets('用回默认形象：服务端和手机上都删掉；退出登录也从手机上删掉', (tester) async {
      final png = await stickerPng(tester);
      final api = AvatarApi();
      final store = MemoryAvatarStore()..png = png;
      final state = await newState(prefs: {'token': 't'}, api: api, store: store);
      await tester.runAsync(state.loadAvatar);
      expect(state.avatar, isNotNull);

      await tester.runAsync(state.clearAvatar);
      expect(api.deletes, 1);
      expect(store.png, isNull);
      expect(state.avatar, isNull);

      store.png = png;
      await tester.runAsync(state.loadAvatar);
      await tester.runAsync(state.logout);
      expect(store.png, isNull);
      expect(state.avatar, isNull);
    });

    testWidgets('设置页填导出码导入，形象换成照片形象；再用回默认', (tester) async {
      final api = AvatarApi()..importPng = await stickerPng(tester);
      final state = await newState(api: api);
      await pumpSettings(tester, state);
      expect(find.text('现在是默认形象'), findsOneWidget);
      expect(find.byType(PhotoWeatherAvatar), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, '导入'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'abcd-efgh');
      await tapAndWait(tester, find.widgetWithText(PopButton, '导入'), () => state.avatar != null);

      expect(api.imports, ['abcd-efgh']);
      expect(find.byType(ImportAvatarSheet), findsNothing);
      expect(find.text('用的是导入的形象'), findsOneWidget);
      expect(find.byType(PhotoWeatherAvatar), findsOneWidget);

      await tester.tap(find.text('用回默认形象'));
      await tester.pumpAndSettle();
      await tapAndWait(tester, find.text('用回默认'), () => state.avatar == null);
      expect(find.text('现在是默认形象'), findsOneWidget);
    });

    testWidgets('设置页导入失败时在输入框下面说原因', (tester) async {
      final api = AvatarApi()..importError = ApiException('导出码不对或已经过期，回“再玩我是狗”重新生成一个', statusCode: 422);
      final state = await newState(api: api);
      await pumpSettings(tester, state);

      await tester.tap(find.widgetWithText(TextButton, '导入'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ABCDEFGH');
      await tapAndWait(tester, find.widgetWithText(PopButton, '导入'), () => api.imports.isNotEmpty);

      expect(find.text('导出码不对或已经过期，回“再玩我是狗”重新生成一个'), findsOneWidget);
      expect(state.avatar, isNull);
    });
  });

  group('关心群里别人的形象', () {
    testWidgets('TA 导入过形象就下载下来叠天气；没有就用默认形象', (tester) async {
      const url = 'https://cdn.example.com/avatars/2/b.png';
      final api = AvatarApi()..remote[url] = await stickerPng(tester);
      final state = await newState(api: api);
      // 先在真实的异步里把图下载、解码好（同一个地址只下载一次）
      await tester.runAsync(() => state.memberAvatar(url));

      await tester.pumpWidget(AppScope(
        state: state,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(children: [
            MemberWeatherAvatar(avatarUrl: url, temp: WeatherTemp.cold, cond: WeatherCond.snow),
            MemberWeatherAvatar(avatarUrl: null, temp: WeatherTemp.cold, cond: WeatherCond.snow),
          ]),
        ),
      ));
      // 图是在真实的异步里下载好的，让 FutureBuilder 在真实的异步里收到结果
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(find.byType(PhotoWeatherAvatar), findsOneWidget);
      expect(find.byType(WeatherAvatar), findsOneWidget);
      expect(api.downloads, [url]);
    });
  });
}
