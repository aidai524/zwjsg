import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pop_ui/pop_ui.dart';
import 'package:series_share/series_share.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zwjsg_app/core/api_client.dart';
import 'package:zwjsg_app/core/app_state.dart';
import 'package:zwjsg_app/core/groups.dart';
import 'package:zwjsg_app/features/group/group_detail_page.dart';
import 'package:zwjsg_app/features/group/group_page.dart';
import 'package:zwjsg_app/features/group/king_card_page.dart';
import 'package:zwjsg_app/widgets/nudge_listener.dart';

import 'widget_test.dart' show pumpApp, usePhoneScreen;

const me = GroupMember(id: 1, nickname: '我', isMe: true, isOwner: true, today: MemberToday(dogPercent: 20, stage: 0));
const dog = GroupMember(
    id: 2, nickname: '阿强', today: MemberToday(dogPercent: 140, stage: 4, breedKey: 'husky'), nudgesLeft: 2);
const shy = GroupMember(id: 3, nickname: '害羞的', hidden: true, nudgesLeft: 2);
const quiet = GroupMember(id: 4, nickname: '用苹果的', nudgesLeft: 0);

const sample = GroupInfo(
  id: 7,
  name: '宿舍狗窝',
  inviteCode: 'ABCD2345',
  isOwner: true,
  members: [dog, me, quiet, shy],
  king: KingOfDay(userId: 2, nickname: '阿强', date: '2026-11-19', dogPercent: 150, stage: 5, breedKey: 'husky'),
  team: TeamStatus(streak: 3, best: 3, human: 1, dog: 1, unknown: 2),
);

class GroupApi extends ApiClient {
  List<GroupInfo> list = [];
  GroupInfo detail = sample;
  final calls = <String>[];
  int nudgesLeft = 2;
  List<NudgeNote> inbox = [];
  final seen = <int>[];

  @override
  Future<List<GroupInfo>> groups() async {
    calls.add('groups');
    return list;
  }

  @override
  Future<GroupInfo> group(int id) async {
    calls.add('group $id');
    return detail;
  }

  @override
  Future<GroupInfo> createGroup(String name) async {
    calls.add('create $name');
    detail = GroupInfo(id: 8, name: name, inviteCode: 'WXYZ6789', isOwner: true, members: const [me]);
    list = [detail];
    return detail;
  }

  @override
  Future<GroupInfo> joinGroup(String inviteCode) async {
    calls.add('join $inviteCode');
    if (inviteCode != 'ABCD2345') throw ApiException('邀请码不对', statusCode: 422);
    list = [sample];
    return sample;
  }

  @override
  Future<GroupInfo> updateMyGroupSettings(int id, {bool? hideStatus, bool? muteNudges}) async {
    calls.add('me hide=$hideStatus mute=$muteNudges');
    return detail;
  }

  @override
  Future<void> leaveGroup(int id) async {
    calls.add('leave $id');
    list = [];
  }

  @override
  Future<int> nudge(int groupId, int recipientId) async {
    calls.add('nudge $recipientId');
    return --nudgesLeft;
  }

  @override
  Future<List<NudgeNote>> nudgeInbox() async => inbox;

  @override
  Future<void> markNudgesSeen(List<int> ids) async => seen.addAll(ids);

  @override
  Future<Uint8List> downloadAvatar(String url) async => throw ApiException('测试里不下载');
}

class FakeSharer implements TextSharer {
  String? text;

  @override
  Future<bool> share(String text, {Rect? origin}) async {
    this.text = text;
    return true;
  }
}

Future<AppState> newState(GroupApi api, {bool loggedIn = true}) async {
  SharedPreferences.setMockInitialValues({if (loggedIn) 'token': 't', 'onboarded': true});
  return AppState(await SharedPreferences.getInstance(), api: api);
}

Future<void> pumpGroups(WidgetTester tester, AppState state, {TextSharer? sharer, String at = '/group'}) async {
  usePhoneScreen(tester);
  final router = GoRouter(initialLocation: at, routes: [
    GoRoute(
      path: '/group',
      builder: (_, __) => const GroupPage(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (_, s) =>
              GroupDetailPage(groupId: int.parse(s.pathParameters['id']!), sharer: sharer ?? FakeSharer()),
        ),
      ],
    ),
    GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('登录页'))),
  ]);
  await tester.pumpWidget(AppScope(state: state, child: MaterialApp.router(routerConfig: router, theme: Pop.theme())));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('底部导航的“狗群”改叫“群组”', (tester) async {
    usePhoneScreen(tester);
    await pumpApp(tester, {'onboarded': true});
    expect(find.text('群组'), findsOneWidget);
    expect(find.text('狗群'), findsNothing);
  });

  testWidgets('没登录：说清楚群组是干什么的、只共享什么，先去登录', (tester) async {
    final api = GroupApi();
    await pumpGroups(tester, await newState(api, loggedIn: false));
    expect(find.textContaining('只共享狗度、阶段和犬种'), findsOneWidget);
    expect(api.calls, isEmpty);
    await tester.tap(find.text('登录后建群'));
    await tester.pumpAndSettle();
    expect(find.text('登录页'), findsOneWidget);
  });

  testWidgets('还没群：建个群（用现成的名字），建好直接进群', (tester) async {
    final api = GroupApi();
    await pumpGroups(tester, await newState(api));
    expect(find.text('建个群'), findsOneWidget);

    await tester.tap(find.text('建个群'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打工狗互助会'));
    await tester.tap(find.text('建群'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('create 打工狗互助会'));
    expect(find.byType(GroupDetailPage), findsOneWidget);
    expect(find.text('打工狗互助会'), findsWidgets);
    expect(find.text('WXYZ 6789'), findsOneWidget);
  });

  testWidgets('邀请码不对时说清楚；对了就进群', (tester) async {
    final api = GroupApi();
    await pumpGroups(tester, await newState(api));
    await tester.tap(find.text('用邀请码加入'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wrong123');
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('join WRONG123'));
    expect(find.text('邀请码不对'), findsOneWidget);

    await tester.tap(find.text('用邀请码加入'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abcd2345');
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();
    expect(find.byType(GroupDetailPage), findsOneWidget);
  });

  testWidgets('群列表：每个人今天的样子、今天最狗的是谁、一起做人几天', (tester) async {
    final api = GroupApi()..list = [sample];
    await pumpGroups(tester, await newState(api));
    expect(find.text('宿舍狗窝'), findsOneWidget);
    expect(find.text('一起做人 3 天'), findsOneWidget);
    expect(find.text('4 人 · 今天最狗：阿强 140%'), findsOneWidget);
  });

  testWidgets('群里：最狗的在前，藏起来的、没同步的写清楚；昨天的狗王、一起做人', (tester) async {
    final api = GroupApi();
    await pumpGroups(tester, await newState(api), at: '/group/7');

    expect(find.text('宿舍狗窝'), findsOneWidget);
    for (final label in ['阿强：狗度 140%', '我（我）：还是人 20%', '用苹果的：还没同步', '害羞的：藏起来了']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    expect(find.text('4 / 10 人'), findsOneWidget);
    expect(find.text('完全体狗王，汪！今天先从放下手机开始'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('邀请'), 200);
    expect(find.text('今天：1 人还是人 · 1 人变狗了 · 2 人没同步'), findsOneWidget);
    expect(find.textContaining('只算共享狗度的人'), findsOneWidget);
    // 不是 iPhone：不提示“群里看不到你的狗度”
    expect(find.textContaining('你用的是 iPhone'), findsNothing);
  });

  testWidgets('发邀请：系统分享面板发一段带邀请码的话，不许诺奖励', (tester) async {
    final api = GroupApi();
    final sharer = FakeSharer();
    await pumpGroups(tester, await newState(api), sharer: sharer, at: '/group/7');
    await tester.scrollUntilVisible(find.text('发给好友'), 200);
    await tester.ensureVisible(find.text('发给好友'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发给好友'));
    await tester.pumpAndSettle();
    expect(sharer.text, GroupDetailPage.inviteText(sample));
    expect(sharer.text, contains('ABCD2345'));
    expect(sharer.text, isNot(contains('奖励')));
  });

  testWidgets('汪一下：点别人，按钮写着今天还能汪几次；汪够了就按不了', (tester) async {
    final api = GroupApi();
    await pumpGroups(tester, await newState(api), at: '/group/7');

    await tester.tap(find.bySemanticsLabel('阿强：狗度 140%'));
    await tester.pumpAndSettle();
    expect(find.textContaining('阶段 4 · 吐舌头 · 狗度 140% · 今天是哈士奇'), findsOneWidget);
    await tester.tap(find.text('汪一下，叫 TA 放下手机（今天还能 2 次）'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('nudge 2'));
    expect(find.text('汪！已经叫 阿强 放下手机了（今天还能汪 1 次）'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('用苹果的：还没同步'));
    await tester.pumpAndSettle();
    expect(find.textContaining('没打开 App，或者用的是 iPhone'), findsOneWidget);
    final button = tester.widget<PopButton>(find.widgetWithText(PopButton, '今天已经汪够了，明天再说'));
    expect(button.onPressed, isNull);
  });

  testWidgets('右上角菜单：隐藏我的狗度；退出群组要确认，退出后回到群列表', (tester) async {
    final api = GroupApi()..list = [sample];
    await pumpGroups(tester, await newState(api));
    await tester.tap(find.text('宿舍狗窝'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐藏我的狗度'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('me hide=true mute=null'));

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出群组'));
    await tester.pumpAndSettle();
    expect(find.text('你是群主，退出后群主会交给最早进群的人。'), findsOneWidget);
    await tester.tap(find.text('退出'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('leave 7'));
    expect(find.byType(GroupDetailPage), findsNothing);
    expect(find.text('建个群'), findsOneWidget);
  });

  group('汪一下的提醒', () {
    test('同一个人汪了几次就写几次', () {
      expect(
        NudgeDialog.lines(const [
          NudgeNote(id: 1, senderNickname: '阿强', groupName: '宿舍狗窝'),
          NudgeNote(id: 2, senderNickname: '阿强', groupName: '宿舍狗窝'),
          NudgeNote(id: 3, senderNickname: '小美', groupName: '相亲相爱一家狗'),
        ]),
        ['阿强（宿舍狗窝） 汪了你 2 次', '小美（相亲相爱一家狗） 汪了你一下'],
      );
    });

    testWidgets('打开 App 时有人汪过就弹出来，点“放下了”标成看过', (tester) async {
      usePhoneScreen(tester);
      final api = GroupApi()
        ..inbox = const [
          NudgeNote(id: 5, senderNickname: '阿强', groupName: '宿舍狗窝'),
          NudgeNote(id: 6, senderNickname: '阿强', groupName: '宿舍狗窝'),
        ];
      final state = await newState(api);
      await tester.pumpWidget(AppScope(
        state: state,
        child: const MaterialApp(home: NudgeListener(child: Scaffold(body: Text('今天页')))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('汪！'), findsOneWidget);
      expect(find.text('阿强（宿舍狗窝） 汪了你 2 次'), findsOneWidget);
      await tester.tap(find.text('放下了'));
      await tester.pumpAndSettle();
      expect(api.seen, [5, 6]);
      expect(find.text('汪！'), findsNothing);
    });

    testWidgets('没登录不去问', (tester) async {
      final api = GroupApi()..inbox = const [NudgeNote(id: 5, senderNickname: '阿强', groupName: '宿舍狗窝')];
      final state = await newState(api, loggedIn: false);
      await tester.pumpWidget(AppScope(
        state: state,
        child: const MaterialApp(home: NudgeListener(child: Scaffold(body: Text('今天页')))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('汪！'), findsNothing);
    });
  });

  testWidgets('狗王调侃卡：名字、狗度、调侃；用拍照形象的标 AI 生成', (tester) async {
    usePhoneScreen(tester);
    final state = await newState(GroupApi());
    const king = KingOfDay(
        userId: 2, nickname: '阿强', avatarUrl: 'https://example.test/a.png', date: '2026-11-19', dogPercent: 150, stage: 5);
    await tester.pumpWidget(AppScope(
      state: state,
      child: const MaterialApp(home: KingCardPage(king: king, groupName: '宿舍狗窝')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('昨日狗王'), findsOneWidget);
    expect(find.text('阿强'), findsOneWidget);
    expect(find.textContaining('狗度 150%'), findsOneWidget);
    expect(find.text(KingCardPage.roastFor(5)), findsOneWidget);
    expect(find.byType(AiTag), findsOneWidget);
  });
}
