import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:avatar_engine/avatar_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pop_ui/pop_ui.dart';
import 'package:series_share/series_share.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shenme_tianqi/app.dart';
import 'package:shenme_tianqi/core/api_client.dart';
import 'package:shenme_tianqi/core/app_state.dart';
import 'package:shenme_tianqi/core/models.dart';
import 'package:shenme_tianqi/features/card/weather_card_page.dart';
import 'package:shenme_tianqi/features/home/home_page.dart';
import 'package:shenme_tianqi/widgets/common.dart';

import 'avatar_import_test.dart' show MemoryAvatarStore, stickerPng;

/// 1x1 的 PNG，当作截出来的卡片
final onePixelPng =
    base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

/// 接口给的天气：现在 9°、体感 7°、今天 2–12°，晴，8 点的实况
Map<String, dynamic> weatherJson({bool serious = false}) => {
      'now': {
        'temp': 9, 'feels_like': 7, 'text': '晴', 'humidity': 36, 'wind_dir': '北风', 'wind_scale': 1,
        'obs_time': '2026-11-18T08:00+08:00',
      },
      'hourly': const [],
      'daily': const [
        {'date': '2026-11-18', 'temp_max': 12, 'temp_min': 2, 'text_day': '晴'},
      ],
      'view': {
        'cond': serious ? 'serious' : 'sunny',
        'outfit': {'key': 'cold', 'label': '外套'},
        'serious': serious,
        'serious_warnings': serious
            ? const [
                {'title': '北京市气象台发布大风黄色预警', 'text': '原文', 'sender': '北京市气象台', 'pub_time': '2026-11-18T07:00+08:00', 'color': 'Yellow', 'type_name': '大风'},
              ]
            : const [],
        'quip': '太阳挺大，风也挺大，别被骗了',
        'decisions': const {
          'umbrella': {'verdict': 'no', 'label': '不带', 'reason': '不会下雨'},
          'long_johns': {'verdict': 'yes', 'label': '穿', 'reason': '最低体感约 2°'},
          'car_wash': {'verdict': 'yes', 'label': '洗', 'reason': '未来 3 天无雨'},
          'laundry': {'verdict': 'yes', 'label': '晾', 'reason': '湿度 36%，白天无雨'},
        },
      },
      'attribution': '',
      'attributions': const ['https://developer.qweather.com/attribution.html'],
    };

class CardApi extends WeatherApi {
  bool serious = false;

  @override
  Future<WeatherData> weather(String locationId, {int? level, String? adm, String? unit}) async =>
      WeatherData(weatherJson(serious: serious));
}

/// 截图返回一张真的 PNG，保存、分享时记下来
class FakeExporter implements CardExporter {
  final saved = <Uint8List>[];
  final shared = <Uint8List>[];

  @override
  Future<Uint8List> capture(GlobalKey boundaryKey) async => onePixelPng;

  @override
  Future<void> save(Uint8List png) async => saved.add(png);

  @override
  Future<void> share(Uint8List png, {Rect? origin}) async => shared.add(png);
}

const beijing = City(locationId: '101010100', name: '北京', isHome: true);

Future<AppState> newState(WidgetTester tester, {bool serious = false, bool photo = false, String unit = 'c'}) async {
  SharedPreferences.setMockInitialValues({
    'privacy_version': AppState.privacyVersion,
    'onboarded': true,
    'temp_unit': unit,
    'cities': '[{"location_id":"101010100","name":"北京","is_home":true}]',
  });
  final store = MemoryAvatarStore()..png = photo ? await stickerPng(tester) : null;
  final state = AppState(await SharedPreferences.getInstance(), api: CardApi()..serious = serious, avatars: store);
  await tester.runAsync(state.loadAvatar);
  await state.loadWeather(beijing);
  return state;
}

void useTallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<FakeExporter> pumpCard(WidgetTester tester, AppState state) async {
  useTallPhone(tester);
  final exporter = FakeExporter();
  await tester.pumpWidget(AppScope(
    state: state,
    child: MaterialApp(
      theme: Pop.theme(),
      home: WeatherCardPage(locationId: beijing.locationId, exporter: exporter, now: DateTime(2026, 11, 18, 9)),
    ),
  ));
  await tester.pumpAndSettle();
  return exporter;
}

void main() {
  testWidgets('天气卡：城市、日期和实况时间、温度、吐槽、四张决策卡的结论、和风的署名', (tester) async {
    final exporter = await pumpCard(tester, await newState(tester));

    expect(find.text('北京'), findsOneWidget);
    expect(find.text('11 月 18 日 周三 · 08:00 实况'), findsOneWidget);
    expect(find.text('9°'), findsOneWidget);
    expect(find.text('太阳挺大，风也挺大，别被骗了'), findsOneWidget);
    expect(find.text('晴 · 体感 7° · 2°～12°'), findsOneWidget);
    for (final chip in ['伞 不带', '秋裤 穿', '洗车 洗', '晾衣 晾']) {
      expect(find.text(chip), findsOneWidget, reason: chip);
    }
    expect(find.text(QWeatherCredit.label), findsOneWidget);
    expect(find.byType(WeatherAvatar), findsOneWidget);
    // 默认形象是代码画的，不是 AI 生成的，不加标识
    expect(find.text('AI生成'), findsNothing);

    await tester.tap(find.text('保存图片'));
    await tester.pumpAndSettle();
    expect(exporter.saved, [onePixelPng]);
    expect(find.text('已保存到相册'), findsOneWidget);

    await tester.tap(find.text('晒给朋友'));
    await tester.pumpAndSettle();
    expect(exporter.shared, hasLength(1));
    expect(AigcLabel.read(exporter.shared.single), isNull);
  });

  testWidgets('用了导入的照片形象：右下角标“AI生成”，存下来的图片带隐式标识', (tester) async {
    final exporter = await pumpCard(tester, await newState(tester, photo: true));
    expect(find.byType(PhotoWeatherAvatar), findsOneWidget);
    expect(find.text('AI生成'), findsOneWidget);
    // 文字高度不低于卡片宽的 5%
    final cardWidth = tester.getSize(find.byType(WeatherCard)).width;
    final tag = tester.widget<Text>(find.text('AI生成'));
    expect(tag.style!.fontSize! >= cardWidth * 0.05, isTrue, reason: '卡片宽 $cardWidth');

    await tester.tap(find.text('保存图片'));
    await tester.pumpAndSettle();
    final label = AigcLabel.read(exporter.saved.single)!;
    expect(label['Label'], '1');
    expect(label['ContentProducer'], WeatherCardPage.aigcProducer);
  });

  testWidgets('选了华氏度，卡上的温度跟着换算', (tester) async {
    await pumpCard(tester, await newState(tester, unit: 'f'));
    expect(find.text('48°'), findsOneWidget);
    expect(find.text('晴 · 体感 45° · 36°～54°'), findsOneWidget);
  });

  testWidgets('预警期间不生成卡片，也没有保存和分享', (tester) async {
    await pumpCard(tester, await newState(tester, serious: true));
    expect(find.byType(WeatherCard), findsNothing);
    expect(find.textContaining('预警期间不生成带吐槽的卡片'), findsOneWidget);
    expect(find.text('保存图片'), findsNothing);
    expect(find.text('晒给朋友'), findsNothing);
  });

  testWidgets('首页右上角“晒一下”打开天气卡；预警时不显示', (tester) async {
    useTallPhone(tester);
    final state = await newState(tester);
    await tester.pumpWidget(AppScope(state: state, child: ShenmeTianqiApp(state: state)));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('晒一下'));
    await tester.pumpAndSettle();
    expect(find.byType(WeatherCardPage), findsOneWidget);
    expect(find.byType(WeatherCard), findsOneWidget);

    final serious = await newState(tester, serious: true);
    await tester.pumpWidget(AppScope(state: serious, child: ShenmeTianqiApp(state: serious)));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('晒一下'), findsNothing);
  });

  test('天气卡上决策卡的短名字和四张决策卡对得上', () {
    expect(WeatherCard.shortTitles.keys.toSet(), {'umbrella', 'long_johns', 'car_wash', 'laundry'});
  });

  testWidgets('卡片截图在 3 倍下能真的导出 PNG', (tester) async {
    final state = await newState(tester);
    useTallPhone(tester);
    final key = GlobalKey();
    await tester.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(
        theme: Pop.theme(),
        home: Center(
          child: SizedBox(
            width: 300,
            height: 400,
            child: RepaintBoundary(
              key: key,
              child: WeatherCard(city: beijing, weather: state.weatherOf(beijing.locationId)!, now: DateTime(2026, 11, 18), width: 300),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final size = await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final codec = await ui.instantiateImageCodec(data!.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    });
    expect(size, const Size(900, 1200));
  });
}
