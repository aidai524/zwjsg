import 'package:series_core/series_core.dart';

import 'groups.dart';

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

  /// 已解锁的犬种：key → 第一次解锁的日期（yyyy-MM-dd）
  Future<Map<String, String>> breedUnlocks() => request(
        () => dio.get('/breeds'),
        (d) => {
          for (final b in ((d as Map)['breeds'] as List).cast<Map>())
            if (b['unlocked'] == true) b['key'].toString(): (b['unlocked_on'] ?? '').toString(),
        },
      );

  // MARK: 群组（原“狗群”）。群里只有狗度、阶段和犬种

  static GroupInfo _groupData(dynamic d) => GroupInfo.fromJson((d as Map)['data'] as Map);

  Future<List<GroupInfo>> groups() => request(
        () => dio.get('/groups'),
        (d) => [for (final g in (d as Map)['data'] as List) GroupInfo.fromJson(g as Map)],
      );

  Future<GroupInfo> group(int id) => request(() => dio.get('/groups/$id'), _groupData);

  Future<GroupInfo> createGroup(String name) => request(() => dio.post('/groups', data: {'name': name}), _groupData);

  Future<GroupInfo> joinGroup(String inviteCode) =>
      request(() => dio.post('/groups/join', data: {'invite_code': inviteCode}), _groupData);

  Future<GroupInfo> renameGroup(int id, String name) =>
      request(() => dio.patch('/groups/$id', data: {'name': name}), _groupData);

  /// 我在这个群里的设置：隐藏自己的狗度、关掉汪一下
  Future<GroupInfo> updateMyGroupSettings(int id, {bool? hideStatus, bool? muteNudges}) => request(
        () => dio.patch('/groups/$id/me', data: {
          if (hideStatus != null) 'hide_status': hideStatus,
          if (muteNudges != null) 'mute_nudges': muteNudges,
        }),
        _groupData,
      );

  Future<void> leaveGroup(int id) => request(() => dio.post('/groups/$id/leave'), (_) {});

  /// 汪一下，返回今天还能汪 TA 几次
  Future<int> nudge(int groupId, int recipientId) => request(
        () => dio.post('/groups/$groupId/nudges', data: {'recipient_id': recipientId}),
        (d) => ((d as Map)['nudges_left'] as num).toInt(),
      );

  /// 别人汪我、我还没看过的
  Future<List<NudgeNote>> nudgeInbox() => request(
        () => dio.get('/nudges/inbox'),
        (d) => [for (final n in (d as Map)['data'] as List) NudgeNote.fromJson(n as Map)],
      );

  Future<void> markNudgesSeen(List<int> ids) => request(() => dio.post('/nudges/seen', data: {'ids': ids}), (_) {});

  /// 生成导出码，把卡通形象一次性导给“什么鬼天气”：8 位，10 分钟内有效，只能用一次。
  /// 上传和下载形象（uploadAvatar、downloadAvatar）在 series_core 里，两个 App 共用
  Future<({String code, DateTime expiresAt})> exportAvatar() => request(
        () => dio.post('/me/avatar/export'),
        (d) {
          final data = (d as Map)['data'] as Map;
          return (code: data['code'] as String, expiresAt: DateTime.parse(data['expires_at'] as String));
        },
      );
}
