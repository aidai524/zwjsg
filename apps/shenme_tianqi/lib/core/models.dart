// 接口数据模型。只做解析，不做判断：带不带伞、严肃模式等结论都以服务端为准。

int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
int? _ni(dynamic v) => v == null ? null : _i(v);
String _s(dynamic v) => v?.toString() ?? '';
List<String> _strings(dynamic v) => v is List ? v.map(_s).toList() : const [];
List<Map<String, dynamic>> _list(dynamic v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];

/// 关注的城市。游客存在本机；登录后同步到服务端（serverId 不为空）
class City {
  const City({required this.locationId, required this.name, this.adm, this.isHome = false, this.serverId, this.expiresAt});

  final String locationId;
  final String name;
  final String? adm;
  final bool isHome;
  final int? serverId;

  /// 临时城市（出差、旅行时看几天）到这个时间自动移除：本地日期某天的 0 点。长期关注的是 null。
  /// 常驻城市不能是临时的
  final DateTime? expiresAt;

  factory City.fromJson(Map<String, dynamic> j) => City(
        locationId: _s(j['location_id']),
        name: _s(j['name']),
        adm: j['adm'] as String?,
        isHome: j['is_home'] == true,
        serverId: j['id'] is num ? (j['id'] as num).toInt() : null,
        expiresAt: j['expires_at'] == null ? null : DateTime.tryParse(j['expires_at'].toString())?.toLocal(),
      );

  Map<String, dynamic> toJson() => {
        'location_id': locationId,
        'name': name,
        'adm': adm,
        'is_home': isHome,
        if (serverId != null) 'id': serverId,
        if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
      };

  City copyWith({bool? isHome, int? serverId, DateTime? expiresAt, bool permanent = false}) => City(
        locationId: locationId,
        name: name,
        adm: adm,
        isHome: isHome ?? this.isHome,
        serverId: serverId ?? this.serverId,
        expiresAt: permanent ? null : (expiresAt ?? this.expiresAt),
      );

  bool get isTemporary => expiresAt != null;

  bool isExpired(DateTime now) => expiresAt != null && !now.isBefore(expiresAt!);

  /// 还能看几天（含今天）：明天 0 点到期是 1 天，今天就到期了是 0
  int daysLeft(DateTime now) {
    final end = expiresAt;
    if (end == null) return 0;
    // 按日期数，用 UTC 构造避开夏令时
    final days = DateTime.utc(end.year, end.month, end.day).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
    return days < 0 ? 0 : days;
  }

  /// 临时看 [days] 天：今天算第 1 天，看到第 [days] 天结束（第 days + 1 天 0 点到期）
  static DateTime expiryFor(int days, DateTime now) => DateTime(now.year, now.month, now.day + days);
}

class CityHit {
  const CityHit({required this.locationId, required this.name, this.adm, this.adm2});
  final String locationId;
  final String name;
  final String? adm;
  final String? adm2;

  factory CityHit.fromJson(Map<String, dynamic> j) =>
      CityHit(locationId: _s(j['location_id']), name: _s(j['name']), adm: j['adm'] as String?, adm2: j['adm2'] as String?);

  /// “广州 · 广东省”；区县显示上级城市
  String get subtitle => [if (adm2 != null && adm2 != name) adm2, if (adm != null && adm != adm2) adm].join(' · ');
}

class Decision {
  const Decision({required this.verdict, required this.label, required this.reason, this.pop, this.hour});
  final String verdict;
  final String label;
  final String reason;
  final int? pop;
  final int? hour;

  factory Decision.fromJson(Map<String, dynamic>? j) => Decision(
        verdict: _s(j?['verdict']),
        label: _s(j?['label']),
        reason: _s(j?['reason']),
        pop: _ni(j?['pop']),
        hour: _ni(j?['hour']),
      );

  /// “该做”的决定（带伞、穿秋裤），卡片用黄色高亮
  bool get isAction => verdict == 'take' || verdict == 'sun' || verdict == 'yes';
}

/// 气象部门发布的预警：原文照登，不改写
class Warning {
  const Warning({required this.title, required this.text, required this.sender, required this.pubTime, required this.color, required this.typeName});
  final String title;
  final String text;
  final String sender;
  final String pubTime;
  final String color;
  final String typeName;

  /// 一条预警的标识：接口没给 id，用标题（带发布单位和预警种类）加发布时间
  String get key => '$title|$pubTime';

  factory Warning.fromJson(Map<String, dynamic> j) => Warning(
        title: _s(j['title']),
        text: _s(j['text']),
        sender: _s(j['sender']),
        pubTime: _s(j['pub_time']),
        color: _s(j['color']),
        typeName: _s(j['type_name']),
      );
}

class HourItem {
  const HourItem({required this.time, required this.temp, required this.text, this.pop});
  final DateTime time;
  final int temp;
  final String text;
  final int? pop;
}

class DayItem {
  const DayItem({required this.date, required this.max, required this.min, required this.text});
  final DateTime date;
  final int max;
  final int min;
  final String text;
}

class WeatherData {
  WeatherData(this.raw)
      : view = Map<String, dynamic>.from(raw['view'] as Map? ?? const {}),
        now = Map<String, dynamic>.from(raw['now'] as Map? ?? const {});

  final Map<String, dynamic> raw;
  final Map<String, dynamic> view;
  final Map<String, dynamic> now;

  int get temp => _i(now['temp']);
  int get feelsLike => _i(now['feels_like']);
  String get text => _s(now['text']);
  int get humidity => _i(now['humidity']);
  String get wind => '${_s(now['wind_dir'])} ${_i(now['wind_scale'])} 级';
  String? get obsTime => now['obs_time'] as String?;

  String get cond => _s(view['cond']);
  String get outfitKey => _s((view['outfit'] as Map?)?['key']);
  String get outfitLabel => _s((view['outfit'] as Map?)?['label']);
  bool get serious => view['serious'] == true;
  String? get quip => view['quip'] as String?;
  String get attribution => _s(raw['attribution']);

  /// 和风要求原样显示的归因内容，见 QWeatherCredit
  List<String> get attributions => _strings(raw['attributions']);

  List<Warning> get seriousWarnings => _list(view['serious_warnings']).map(Warning.fromJson).toList();
  List<Warning> get bannerWarnings => _list(view['banner_warnings']).map(Warning.fromJson).toList();

  Decision decision(String key) => Decision.fromJson((view['decisions'] as Map?)?[key] as Map<String, dynamic>?);

  List<HourItem> get hourly => _list(raw['hourly'])
      .map((h) => HourItem(time: DateTime.parse(_s(h['time'])), temp: _i(h['temp']), text: _s(h['text']), pop: _ni(h['pop'])))
      .toList();

  List<DayItem> get daily => _list(raw['daily'])
      .map((d) => DayItem(date: DateTime.parse(_s(d['date'])), max: _i(d['temp_max']), min: _i(d['temp_min']), text: _s(d['text_day'])))
      .toList();

  int? get todayMax => daily.isEmpty ? null : daily.first.max;
  int? get todayMin => daily.isEmpty ? null : daily.first.min;

  Map<String, dynamic>? get air => raw['air'] == null ? null : Map<String, dynamic>.from(raw['air'] as Map);
}

class Phrase {
  const Phrase({required this.key, required this.text, required this.topic});
  final String key;
  final String text;
  final String topic;

  factory Phrase.fromJson(Map<String, dynamic> j) => Phrase(key: _s(j['key']), text: _s(j['text']), topic: _s(j['topic']));
}

class GroupBrief {
  const GroupBrief({required this.id, required this.name, required this.membersCount});
  final int id;
  final String name;
  final int membersCount;

  factory GroupBrief.fromJson(Map<String, dynamic> j) =>
      GroupBrief(id: _i(j['id']), name: _s(j['name']), membersCount: _i(j['members_count']));
}

class Member {
  const Member({
    required this.id,
    required this.nickname,
    required this.isMe,
    this.city,
    this.remainingToday,
    this.lastAckAt,
    this.weather,
    this.avatarUrl,
  });

  final int id;
  final String nickname;
  final bool isMe;
  final String? city;
  final int? remainingToday;
  final String? lastAckAt;
  final Map<String, dynamic>? weather;

  /// TA 导入过“再玩我是狗”的形象时，服务端给的图片地址
  final String? avatarUrl;

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        id: _i(j['id']),
        nickname: _s(j['nickname']),
        isMe: j['is_me'] == true,
        city: j['city'] as String?,
        remainingToday: _ni(j['remaining_today']),
        lastAckAt: j['last_ack_at'] as String?,
        weather: j['weather'] == null ? null : Map<String, dynamic>.from(j['weather'] as Map),
        avatarUrl: j['avatar_url'] as String?,
      );

  int? get temp => _ni(weather?['temp']);
  String get weatherText => _s(weather?['text']);
  String get cond => _s(weather?['cond']);
  String get outfit => _s(weather?['outfit']);
  String get fact => _s(weather?['fact']);
  String? get alert => weather?['alert'] as String?;
  List<Phrase> get phrases => _list(weather?['phrases']).map(Phrase.fromJson).toList();
  List<String> get attributions => _strings(weather?['attributions']);
}

class GroupDetail {
  const GroupDetail({required this.id, required this.name, required this.inviteCode, required this.isOwner, required this.maxMembers, required this.members});
  final int id;
  final String name;
  final String inviteCode;
  final bool isOwner;
  final int maxMembers;
  final List<Member> members;

  factory GroupDetail.fromJson(Map<String, dynamic> j) => GroupDetail(
        id: _i(j['id']),
        name: _s(j['name']),
        inviteCode: _s(j['invite_code']),
        isOwner: j['is_owner'] == true,
        maxMembers: _i(j['max_members']),
        members: _list(j['members']).map(Member.fromJson).toList(),
      );
}

class SentReminder {
  const SentReminder({required this.id, required this.status, required this.deliverAt, required this.remainingToday});
  final int id;
  final String status; // scheduled / delivered / acked
  final DateTime deliverAt;
  final int remainingToday;

  factory SentReminder.fromJson(Map<String, dynamic> j) => SentReminder(
        id: _i(j['id']),
        status: _s(j['status']),
        deliverAt: DateTime.parse(_s(j['deliver_at'])).toLocal(),
        remainingToday: _i(j['remaining_today']),
      );
}

class InboxItem {
  const InboxItem({required this.id, required this.sender, required this.text, required this.deliveredAt, required this.acked, this.senderId});
  final int id;
  final String sender;
  final int? senderId;
  final String text;
  final DateTime deliveredAt;
  final bool acked;

  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
        id: _i(j['id']),
        sender: (j['senders'] is List && (j['senders'] as List).isNotEmpty)
            ? (j['senders'] as List).join('、')
            : (_s((j['sender'] as Map?)?['nickname']).isEmpty ? '一位家人' : _s((j['sender'] as Map?)?['nickname'])),
        senderId: _ni((j['sender'] as Map?)?['id']),
        text: _s(j['text']),
        deliveredAt: DateTime.parse(_s(j['delivered_at'])).toLocal(),
        acked: j['acked'] == true,
      );
}

/// 推送设置（登录后才有，存在服务端：早安播报和预警都按常驻城市在服务端生成）
class PushSettings {
  const PushSettings({
    this.morningOn = true,
    this.weekday = '07:30',
    this.weekend = '09:00',
    this.alertOn = true,
  });

  /// 每天早上推一句话天气
  final bool morningOn;

  /// 早安播报的时间，HH:mm；工作日和周末分开
  final String weekday;
  final String weekend;

  /// 黄色及以上预警推一次
  final bool alertOn;

  static bool _bool(dynamic v, bool fallback) => switch (v) {
        bool b => b,
        num n => n != 0,
        String s => s == '1' || s == 'true',
        _ => fallback,
      };

  /// 服务端给的可能是 07:30 或 07:30:00
  static String _hhmm(dynamic v, String fallback) {
    final m = RegExp(r'^(\d{2}):(\d{2})').firstMatch(_s(v));
    return m == null ? fallback : '${m[1]}:${m[2]}';
  }

  factory PushSettings.fromJson(Map<String, dynamic> j) => PushSettings(
        morningOn: _bool(j['morning_push_on'], true),
        weekday: _hhmm(j['morning_push_weekday'], '07:30'),
        weekend: _hhmm(j['morning_push_weekend'], '09:00'),
        alertOn: _bool(j['alert_push_on'], true),
      );

  PushSettings copyWith({bool? morningOn, String? weekday, String? weekend, bool? alertOn}) => PushSettings(
        morningOn: morningOn ?? this.morningOn,
        weekday: weekday ?? this.weekday,
        weekend: weekend ?? this.weekend,
        alertOn: alertOn ?? this.alertOn,
      );

  /// 和 [old] 不一样的字段，用接口的字段名
  Map<String, dynamic> changesFrom(PushSettings old) => {
        if (morningOn != old.morningOn) 'morning_push_on': morningOn,
        if (weekday != old.weekday) 'morning_push_weekday': weekday,
        if (weekend != old.weekend) 'morning_push_weekend': weekend,
        if (alertOn != old.alertOn) 'alert_push_on': alertOn,
      };
}
