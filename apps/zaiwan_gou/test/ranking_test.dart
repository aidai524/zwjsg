import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zwjsg_app/core/api_client.dart';
import 'package:zwjsg_app/core/usage_channel.dart';
import 'package:zwjsg_app/features/today/ranking_page.dart';

/// 记下发出去的请求，不连网
class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString('{"newly_unlocked":[]}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Future<void> pumpRanking(WidgetTester tester, Future<List<AppUsage>> Function() loader) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: RankingPage(loader: loader)));
  await tester.pumpAndSettle();
}

void main() {
  // 隐私约定：App 名称只在手机上显示，上报给服务端的只有狗度、分钟数和犬种
  test('上报每日结果只带狗度、分钟数和犬种，不带任何 App 名称', () async {
    final api = ApiClient();
    final adapter = _RecordingAdapter();
    api.dio.httpClientAdapter = adapter;

    await api.putDailyRecord(date: '2026-11-14', dogPercent: 60, minutesUsed: 108, breedKey: 'corgi');

    final request = adapter.requests.single;
    expect(request.method, 'PUT');
    expect(request.path, '/daily-records/2026-11-14');
    expect(request.data, {'dog_percent': 60, 'minutes_used': 108, 'breed_key': 'corgi'});
  });

  testWidgets('今日排行按用时列出 App，并说明不上传', (tester) async {
    await pumpRanking(tester, () async => const [
          AppUsage(package: 'com.example.video', label: '某短视频', minutes: 95),
          AppUsage(package: 'com.example.chat', label: '某聊天', minutes: 42),
        ]);

    expect(find.text(RankingPage.privacyNote), findsOneWidget);
    expect(find.text('某短视频'), findsOneWidget);
    expect(find.text('1 小时 35 分'), findsOneWidget);
    expect(find.text('某聊天'), findsOneWidget);
    expect(find.text('42 分钟'), findsOneWidget);
    expect(tester.getTopLeft(find.text('某短视频')).dy, lessThan(tester.getTopLeft(find.text('某聊天')).dy));
  });

  testWidgets('没有使用情况访问权限时引导去打开', (tester) async {
    await pumpRanking(tester, () async => throw PlatformException(code: 'NO_PERMISSION'));

    expect(find.text('还差一步：打开“使用情况访问权限”'), findsOneWidget);
    expect(find.text('去打开'), findsOneWidget);
  });

  testWidgets('今天还没用满 1 分钟的 App 时给个说明', (tester) async {
    await pumpRanking(tester, () async => const []);

    expect(find.text('今天还没有用满 1 分钟的 App'), findsOneWidget);
  });
}
