import 'package:avatar_engine/avatar_engine.dart' show AvatarPreset;

import 'dog_meter.dart';

/// 群组（原“狗群”）里服务端给的数据。群里只有狗度、阶段和犬种，没有分钟数，也没有任何 App 明细。

/// 一个人今天的状态（按 TA 自己本地的今天）
class MemberToday {
  const MemberToday({required this.dogPercent, required this.stage, this.breedKey});

  factory MemberToday.fromJson(Map<dynamic, dynamic> m) => MemberToday(
        dogPercent: (m['dog_percent'] as num).toInt(),
        stage: (m['stage'] as num).toInt(),
        breedKey: m['breed_key'] as String?,
      );

  final int dogPercent;
  final int stage;
  final String? breedKey;

  bool get human => DogMeter.isHuman(dogPercent);
}

class GroupMember {
  const GroupMember({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    this.avatarPreset,
    this.isMe = false,
    this.isOwner = false,
    this.hidden = false,
    this.today,
    this.nudgesLeft,
  });

  factory GroupMember.fromJson(Map<dynamic, dynamic> m) => GroupMember(
        id: (m['id'] as num).toInt(),
        nickname: m['nickname'] as String,
        avatarUrl: m['avatar_url'] as String?,
        avatarPreset: AvatarPreset.byName(m['avatar_preset'] as String?),
        isMe: m['is_me'] as bool? ?? false,
        isOwner: m['is_owner'] as bool? ?? false,
        hidden: m['hidden'] as bool? ?? false,
        today: m['today'] == null ? null : MemberToday.fromJson(m['today'] as Map),
        nudgesLeft: (m['nudges_left'] as num?)?.toInt(),
      );

  final int id;
  final String nickname;

  /// TA 的拍照形象；TA 用着预设形象时服务端不给
  final String? avatarUrl;

  /// TA 挑的预设形象；用着拍照形象、或者没挑过是 null
  final AvatarPreset? avatarPreset;
  final bool isMe;
  final bool isOwner;

  /// TA 隐藏了自己的狗度（自己看自己时照样有 [today]）
  final bool hidden;

  /// 今天的状态；还没同步、或者隐藏了时为 null
  final MemberToday? today;

  /// 今天还能汪 TA 几次；自己是 null
  final int? nudgesLeft;
}

/// 某天的狗王：那天群里狗度最高的人
class KingOfDay {
  const KingOfDay({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
    this.avatarPreset,
    required this.date,
    required this.dogPercent,
    required this.stage,
    this.breedKey,
  });

  factory KingOfDay.fromJson(Map<dynamic, dynamic> m) => KingOfDay(
        userId: (m['user_id'] as num).toInt(),
        nickname: m['nickname'] as String,
        avatarUrl: m['avatar_url'] as String?,
        avatarPreset: AvatarPreset.byName(m['avatar_preset'] as String?),
        date: m['date'] as String,
        dogPercent: (m['dog_percent'] as num).toInt(),
        stage: (m['stage'] as num).toInt(),
        breedKey: m['breed_key'] as String?,
      );

  final int userId;
  final String nickname;
  final String? avatarUrl;
  final AvatarPreset? avatarPreset;
  final String date;
  final int dogPercent;
  final int stage;
  final String? breedKey;
}

/// 一起做人：全群连续几天都是人
class TeamStatus {
  const TeamStatus({
    this.streak = 0,
    this.best = 0,
    this.goal = DogMeter.legendStreakDays,
    this.human = 0,
    this.dog = 0,
    this.unknown = 0,
  });

  factory TeamStatus.fromJson(Map<dynamic, dynamic> m) {
    final today = m['today'] as Map? ?? const {};
    int n(Object? v) => (v as num? ?? 0).toInt();
    return TeamStatus(
      streak: n(m['streak']),
      best: n(m['best']),
      goal: n(m['goal'] ?? DogMeter.legendStreakDays),
      human: n(today['human']),
      dog: n(today['dog']),
      unknown: n(today['unknown']),
    );
  }

  final int streak;
  final int best;
  final int goal;

  /// 今天：几个人还是人、几个人变狗了、几个人没同步（或者隐藏了）
  final int human;
  final int dog;
  final int unknown;

  /// 这个群连续做人到过 [goal] 天，拿过“狼群”称号
  bool get wolfPack => best >= goal;
}

class GroupInfo {
  const GroupInfo({
    required this.id,
    required this.name,
    required this.inviteCode,
    this.isOwner = false,
    this.maxMembers = 10,
    this.hideStatus = false,
    this.muteNudges = false,
    this.members = const [],
    this.king,
    this.team = const TeamStatus(),
  });

  factory GroupInfo.fromJson(Map<dynamic, dynamic> m) {
    final me = m['me'] as Map? ?? const {};
    return GroupInfo(
      id: (m['id'] as num).toInt(),
      name: m['name'] as String,
      inviteCode: m['invite_code'] as String,
      isOwner: m['is_owner'] as bool? ?? false,
      maxMembers: (m['max_members'] as num? ?? 10).toInt(),
      hideStatus: me['hide_status'] as bool? ?? false,
      muteNudges: me['mute_nudges'] as bool? ?? false,
      members: [for (final x in m['members'] as List? ?? const []) GroupMember.fromJson(x as Map)],
      king: m['king_yesterday'] == null ? null : KingOfDay.fromJson(m['king_yesterday'] as Map),
      team: m['team'] == null ? const TeamStatus() : TeamStatus.fromJson(m['team'] as Map),
    );
  }

  final int id;
  final String name;
  final String inviteCode;
  final bool isOwner;
  final int maxMembers;

  /// 我在这个群里：隐藏了自己的狗度、关掉了汪一下
  final bool hideStatus;
  final bool muteNudges;

  /// 今天最狗的在前
  final List<GroupMember> members;

  /// 昨天的狗王；昨天大家都是人、或者没人同步时为 null
  final KingOfDay? king;
  final TeamStatus team;

  bool get full => members.length >= maxMembers;

  /// 今天最狗的人（得有数据、已经变狗了）
  GroupMember? get leader {
    for (final m in members) {
      final t = m.today;
      if (t != null && !t.human) return m;
    }
    return null;
  }
}

/// 别人汪了你一下
class NudgeNote {
  const NudgeNote({required this.id, required this.senderNickname, required this.groupName});

  factory NudgeNote.fromJson(Map<dynamic, dynamic> m) => NudgeNote(
        id: (m['id'] as num).toInt(),
        senderNickname: m['sender_nickname'] as String,
        groupName: m['group_name'] as String,
      );

  final int id;
  final String senderNickname;
  final String groupName;
}
