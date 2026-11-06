import 'package:dio/dio.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// 系列共用的接口客户端：请求封装、token、短信登录、退出、注销。
/// 每个 app 继承它、传入自己的后端地址，再加上自己的业务接口。
class SeriesApiClient {
  SeriesApiClient({required String baseUrl, String? token}) : _token = token {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json'},
    ));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final t = _token;
      if (t != null) options.headers['Authorization'] = 'Bearer $t';
      handler.next(options);
    }));
  }

  late final Dio dio;
  String? _token;

  set token(String? value) => _token = value;
  bool get hasToken => _token != null;

  /// 发请求并解析结果；网络错误和后端的错误信息统一转成 [ApiException]
  Future<T> request<T>(Future<Response<dynamic>> Function() req, T Function(dynamic data) parse) async {
    try {
      final res = await req();
      return parse(res.data);
    } on DioException catch (e) {
      final data = e.response?.data;
      final status = e.response?.statusCode;
      if (data is Map && data['message'] is String) {
        throw ApiException(data['message'] as String, statusCode: status);
      }
      throw ApiException('网络不太行，稍后再试', statusCode: status);
    }
  }

  Future<void> sendSms(String phone) =>
      request(() => dio.post('/auth/sms/send', data: {'phone': phone}), (_) {});

  /// 返回 token
  Future<String> smsLogin(String phone, String code) => request(
        () => dio.post('/auth/sms/login', data: {'phone': phone, 'code': code, 'device_name': 'app'}),
        (d) => (d as Map)['token'] as String,
      );

  Future<void> logout() => request(() => dio.post('/auth/logout'), (_) {});

  Future<Map<String, dynamic>> me() =>
      request(() => dio.get('/me'), (d) => Map<String, dynamic>.from((d as Map)['data'] as Map));

  Future<void> updateSettings(Map<String, dynamic> settings) =>
      request(() => dio.patch('/me/settings', data: settings), (_) {});

  Future<void> deleteAccount() => request(() => dio.delete('/me'), (_) {});
}
