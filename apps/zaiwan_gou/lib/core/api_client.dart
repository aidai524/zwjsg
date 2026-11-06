import 'package:series_core/series_core.dart';

export 'package:series_core/series_core.dart' show ApiException;

/// 后端地址：运行时用 --dart-define=API_BASE=https://你的域名/api/v1 覆盖。
/// 默认值 10.0.2.2 是安卓模拟器访问电脑本机的地址。
const String kApiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://10.0.2.2:8000/api/v1');

/// “再玩我是狗”的接口：登录等通用接口来自 [SeriesApiClient]，这里只加本 app 的业务接口。
class ApiClient extends SeriesApiClient {
  ApiClient({super.token}) : super(baseUrl: kApiBase);

  /// 上报某天的结果，返回这次新解锁的犬种 key
  Future<List<String>> putDailyRecord({
    required String date,
    required int dogPercent,
    required int minutesUsed,
    String? breedKey,
  }) =>
      request(
        () => dio.put('/daily-records/$date', data: {
          'dog_percent': dogPercent,
          'minutes_used': minutesUsed,
          'breed_key': breedKey,
        }),
        (d) => ((d as Map)['newly_unlocked'] as List).map((e) => e.toString()).toList(),
      );

  /// 已解锁的犬种 key
  Future<Set<String>> ownedBreeds() => request(
        () => dio.get('/breeds'),
        (d) => ((d as Map)['breeds'] as List)
            .where((b) => (b as Map)['unlocked'] == true)
            .map((b) => (b as Map)['key'].toString())
            .toSet(),
      );
}
