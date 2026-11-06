import 'package:series_core/series_core.dart';

import 'models.dart';

export 'package:series_core/series_core.dart' show ApiException;

/// 后端地址：运行时用 --dart-define=API_BASE=https://你的域名/api/v1 覆盖。
/// 默认值 10.0.2.2 是安卓模拟器访问电脑本机的地址；端口和狗后端错开（8001）。
const String kApiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://10.0.2.2:8001/api/v1');

Map<String, dynamic> _data(dynamic d) => Map<String, dynamic>.from((d as Map)['data'] as Map);
List<Map<String, dynamic>> _dataList(dynamic d) =>
    ((d as Map)['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

/// “什么鬼天气”的接口：登录等通用接口来自 [SeriesApiClient]。
class WeatherApi extends SeriesApiClient {
  WeatherApi({super.token}) : super(baseUrl: kApiBase);

  // ---- 天气（不用登录） ----

  Future<List<CityHit>> searchCities(String q) => request(
        () => dio.get('/cities/search', queryParameters: {'q': q}),
        (d) => _dataList(d).map(CityHit.fromJson).toList(),
      );

  Future<WeatherData> weather(String locationId, {int? level, String? adm}) => request(
        () => dio.get('/weather/$locationId', queryParameters: {
          if (level != null) 'level': level,
          if (adm != null) 'adm': adm,
        }),
        (d) => WeatherData(_data(d)),
      );

  // ---- 城市（登录后同步） ----

  Future<List<City>> cities() => request(() => dio.get('/cities'), (d) => _dataList(d).map(City.fromJson).toList());

  Future<City> addCity(City c) => request(
        () => dio.post('/cities', data: {'location_id': c.locationId, 'name': c.name, 'adm': c.adm, 'is_home': c.isHome}),
        (d) => City.fromJson(_data(d)),
      );

  Future<void> setHomeCity(int serverId) => request(() => dio.patch('/cities/$serverId', data: {'is_home': true}), (_) {});

  Future<void> deleteCity(int serverId) => request(() => dio.delete('/cities/$serverId'), (_) {});

  // ---- 关心群 ----

  Future<List<GroupBrief>> groups() =>
      request(() => dio.get('/care-groups'), (d) => _dataList(d).map(GroupBrief.fromJson).toList());

  Future<GroupDetail> createGroup(String name) =>
      request(() => dio.post('/care-groups', data: {'name': name}), (d) => GroupDetail.fromJson(_data(d)));

  Future<GroupDetail> joinGroup(String code) =>
      request(() => dio.post('/care-groups/join', data: {'invite_code': code}), (d) => GroupDetail.fromJson(_data(d)));

  Future<GroupDetail> group(int id) => request(() => dio.get('/care-groups/$id'), (d) => GroupDetail.fromJson(_data(d)));

  Future<void> leaveGroup(int id) => request(() => dio.post('/care-groups/$id/leave'), (_) {});

  Future<SentReminder> remind({required int groupId, required int recipientId, required String phraseKey}) => request(
        () => dio.post('/reminders', data: {'care_group_id': groupId, 'recipient_id': recipientId, 'phrase_key': phraseKey}),
        (d) => SentReminder.fromJson(_data(d)),
      );

  Future<List<InboxItem>> inbox() =>
      request(() => dio.get('/reminders/inbox'), (d) => _dataList(d).map(InboxItem.fromJson).toList());

  Future<void> ack(int reminderId) => request(() => dio.post('/reminders/$reminderId/ack'), (_) {});

  /// 静音某人（对方不知道）
  Future<void> muteUser(int userId) => request(() => dio.post('/mutes', data: {'muted_user_id': userId}), (_) {});
}
