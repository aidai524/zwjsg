import 'package:dio/dio.dart';

/// 后端地址：运行时用 --dart-define=API_BASE=https://你的域名/api/v1 覆盖。
/// 默认值 10.0.2.2 是安卓模拟器访问电脑本机的地址。
const String kApiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://10.0.2.2:8000/api/v1');

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? token}) : _token = token {
    _dio = Dio(BaseOptions(
      baseUrl: kApiBase,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json'},
    ));
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final t = _token;
      if (t != null) options.headers['Authorization'] = 'Bearer $t';
      handler.next(options);
    }));
  }

  late final Dio _dio;
  String? _token;

  set token(String? value) => _token = value;

  Future<T> _call<T>(Future<Response<dynamic>> Function() req, T Function(dynamic data) parse) async {
    try {
      final res = await req();
      return parse(res.data);
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) throw ApiException(data['message'] as String);
      throw ApiException('网络不太行，稍后再试');
    }
  }

  Future<void> sendSms(String phone) =>
      _call(() => _dio.post('/auth/sms/send', data: {'phone': phone}), (_) {});

  /// 返回 token
  Future<String> smsLogin(String phone, String code) => _call(
        () => _dio.post('/auth/sms/login', data: {'phone': phone, 'code': code, 'device_name': 'app'}),
        (d) => (d as Map)['token'] as String,
      );

  Future<void> logout() => _call(() => _dio.post('/auth/logout'), (_) {});

  Future<Map<String, dynamic>> me() =>
      _call(() => _dio.get('/me'), (d) => Map<String, dynamic>.from((d as Map)['data'] as Map));

  Future<void> updateSettings(Map<String, dynamic> settings) =>
      _call(() => _dio.patch('/me/settings', data: settings), (_) {});

  Future<void> deleteAccount() => _call(() => _dio.delete('/me'), (_) {});

  /// 上报某天的结果，返回这次新解锁的犬种 key
  Future<List<String>> putDailyRecord({
    required String date,
    required int dogPercent,
    required int minutesUsed,
    String? breedKey,
  }) =>
      _call(
        () => _dio.put('/daily-records/$date', data: {
          'dog_percent': dogPercent,
          'minutes_used': minutesUsed,
          'breed_key': breedKey,
        }),
        (d) => ((d as Map)['newly_unlocked'] as List).map((e) => e.toString()).toList(),
      );

  /// 已解锁的犬种 key
  Future<Set<String>> ownedBreeds() => _call(
        () => _dio.get('/breeds'),
        (d) => ((d as Map)['breeds'] as List)
            .where((b) => (b as Map)['unlocked'] == true)
            .map((b) => (b as Map)['key'].toString())
            .toSet(),
      );
}
