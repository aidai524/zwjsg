import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shenme_tianqi/core/api_client.dart';
import 'package:shenme_tianqi/core/app_state.dart';
import 'package:shenme_tianqi/core/home_widget.dart';
import 'package:shenme_tianqi/core/models.dart';
import 'package:shenme_tianqi/core/temp_unit.dart';

import 'avatar_import_test.dart' show AvatarApi, MemoryAvatarStore, stickerPng;

/// 假的原生小组件：记下 App 告诉它的配置和重画次数
class FakeBridge implements HomeWidgetBridge {
  FakeBridge(this.dir);

  final String? dir;
  final configs = <HomeWidgetConfig?>[];
  int reloads = 0;

  @override
  Future<String?> directory() async => dir;

  @override
  Future<void> configure(HomeWidgetConfig? config) async => configs.add(config);

  @override
  Future<void> reload() async => reloads++;
}

const beijing = City(locationId: '101010100', name: '北京', adm: '北京市', isHome: true);
const guangzhou = City(locationId: '101280101', name: '广州', adm: '广东省');

Future<AppState> newState({bool consented = true, List<City> cities = const [beijing, guangzhou], AvatarApi? api}) async {
  SharedPreferences.setMockInitialValues({
    'privacy_version': consented ? AppState.privacyVersion : 0,
    'onboarded': true,
    'cities': jsonEncode(cities.map((c) => c.toJson()).toList()),
  });
  return AppState(await SharedPreferences.getInstance(), api: api ?? AvatarApi(), avatars: MemoryAvatarStore());
}

Directory tempDir() {
  final dir = Directory.systemTemp.createTempSync('home_widget_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

void main() {
  testWidgets('把常驻城市和温度单位告诉小组件；城市删光了就让小组件提示打开 App', (tester) async {
    final state = await newState();
    final bridge = FakeBridge(null);
    final sync = HomeWidgetSync(state, bridge: bridge);

    await tester.runAsync(sync.sync);
    final config = bridge.configs.single!;
    expect(config.toMap(), {'api_base': kApiBase, 'location_id': '101010100', 'city': '北京', 'adm': '北京市', 'unit': 'c'});

    // 没变化就不重复告诉
    await tester.runAsync(sync.sync);
    expect(bridge.configs, hasLength(1));

    await state.setTempUnit(TempUnit.fahrenheit);
    await tester.runAsync(sync.sync);
    expect(bridge.configs.last!.unit, 'f');

    await state.setHome(guangzhou);
    await tester.runAsync(sync.sync);
    expect(bridge.configs.last!.locationId, '101280101');
    expect(bridge.configs.last!.city, '广州');

    for (final c in [...state.cities]) {
      await state.removeCity(c);
    }
    await tester.runAsync(sync.sync);
    expect(bridge.configs.last, isNull);
  });

  testWidgets('没同意隐私政策时小组件不查天气', (tester) async {
    final state = await newState(consented: false);
    final bridge = FakeBridge(null);

    await tester.runAsync(HomeWidgetSync(state, bridge: bridge).sync);
    expect(bridge.configs.single, isNull);
  });

  testWidgets('画好 61 张形象图给小组件挑；形象没变不重画，换了形象重画', (tester) async {
    final dir = tempDir();
    final api = AvatarApi();
    final state = await newState(api: api);
    final bridge = FakeBridge(dir.path);
    final sync = HomeWidgetSync(state, bridge: bridge);

    await tester.runAsync(sync.sync);
    final names = dir.listSync().map((f) => f.uri.pathSegments.last).toSet();
    expect(names, hasLength(62)); // 61 张图 + 版本记录
    expect(names, containsAll(['avatar_hot_sunny.png', 'avatar_freezing_snow.png', 'avatar_mild_light_rain.png', 'avatar_serious.png']));
    expect(names.where((n) => n.endsWith('.tmp')), isEmpty);
    expect(File('${dir.path}/${HomeWidgetSync.versionFile}').readAsStringSync(), 'v$weatherAvatarArtVersion:default');
    expect(bridge.reloads, 1);

    // 图是 360x360 的 PNG
    final size = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(File('${dir.path}/avatar_cool_wind.png').readAsBytesSync());
      final image = (await codec.getNextFrame()).image;
      return (image.width, image.height);
    });
    expect(size, (HomeWidgetSync.avatarPixels, HomeWidgetSync.avatarPixels));

    // 再同步一次：形象没变，不重画
    final before = File('${dir.path}/avatar_serious.png').lastModifiedSync();
    await tester.runAsync(sync.sync);
    expect(bridge.reloads, 1);
    expect(File('${dir.path}/avatar_serious.png').lastModifiedSync(), before);

    // 导入了照片形象：重画
    api.importPng = await stickerPng(tester);
    await tester.runAsync(() => state.importAvatar('ABCD2345'));
    await tester.runAsync(sync.sync);
    expect(bridge.reloads, 2);
    final version = File('${dir.path}/${HomeWidgetSync.versionFile}').readAsStringSync();
    expect(version, startsWith('v$weatherAvatarArtVersion:'));
    expect(version, isNot(endsWith(':default')));

    // 用回默认形象：再重画
    await tester.runAsync(state.clearAvatar);
    await tester.runAsync(sync.sync);
    expect(bridge.reloads, 3);
    expect(File('${dir.path}/${HomeWidgetSync.versionFile}').readAsStringSync(), 'v$weatherAvatarArtVersion:default');
  });

  testWidgets('图被删了（比如重装）会补画', (tester) async {
    final dir = tempDir();
    final bridge = FakeBridge(dir.path);
    final sync = HomeWidgetSync(await newState(), bridge: bridge);

    await tester.runAsync(sync.sync);
    File('${dir.path}/avatar_serious.png').deleteSync();
    await tester.runAsync(sync.sync);
    expect(File('${dir.path}/avatar_serious.png').existsSync(), isTrue);
    expect(bridge.reloads, 2);
  });

  test('形象图的文件名用服务端的衣服档和天气状态', () {
    expect(HomeWidgetSync.avatarStates, hasLength(61));
    expect(HomeWidgetSync.fileName(WeatherTemp.cold, WeatherCond.heavyRain), 'avatar_cold_heavy_rain.png');
    expect(HomeWidgetSync.fileName(WeatherTemp.hot, WeatherCond.serious), 'avatar_serious.png');
  });
}
