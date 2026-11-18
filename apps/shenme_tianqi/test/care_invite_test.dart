import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pop_ui/pop_ui.dart';
import 'package:series_share/series_share.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shenme_tianqi/core/api_client.dart';
import 'package:shenme_tianqi/core/app_state.dart';
import 'package:shenme_tianqi/core/models.dart';
import 'package:shenme_tianqi/features/care/group_page.dart';

import 'avatar_import_test.dart' show MemoryAvatarStore;

/// 服务端：群详情固定返回 [members] 个人
class GroupApi extends WeatherApi {
  GroupApi({this.members = 1});

  final int members;

  @override
  Future<GroupDetail> group(int id, {String? unit}) async => GroupDetail(
        id: id,
        name: '我们家',
        inviteCode: 'ABCD2345',
        isOwner: true,
        maxMembers: 8,
        members: [
          for (var i = 0; i < members; i++) Member(id: i + 1, nickname: i == 0 ? '我' : '家人$i', isMe: i == 0, city: '北京'),
        ],
      );
}

/// 假的分享面板：记下发了什么、从哪弹出；[opens] 为 false 时假装打不开
class FakeSharer implements TextSharer {
  FakeSharer({this.opens = true});

  final bool opens;
  final texts = <String>[];
  final origins = <Rect?>[];

  @override
  Future<bool> share(String text, {Rect? origin}) async {
    texts.add(text);
    origins.add(origin);
    return opens;
  }
}

Future<String?> Function() captureClipboard(WidgetTester tester) {
  String? copied;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return () async => copied;
}

Future<void> pumpGroup(WidgetTester tester, {required TextSharer sharer, int members = 1}) async {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'privacy_version': AppState.privacyVersion, 'onboarded': true, 'token': 't'});
  final state = AppState(await SharedPreferences.getInstance(), api: GroupApi(members: members), avatars: MemoryAvatarStore());
  await tester.pumpWidget(AppScope(
    state: state,
    child: MaterialApp(theme: Pop.theme(), home: GroupPage(groupId: 7, sharer: sharer)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('点“+ 邀请”弹系统分享面板，发一段写清楚怎么加入的话', (tester) async {
    final sharer = FakeSharer();
    await pumpGroup(tester, sharer: sharer);

    await tester.tap(find.text('+ 邀请'));
    await tester.pumpAndSettle();

    final text = sharer.texts.single;
    expect(text, contains('「我们家」'));
    expect(text, contains('用邀请码加入'));
    expect(text, contains('ABCD2345'));
    expect(text, isNot(contains('http')), reason: '还没有下载页，不带链接');
    // iPad 的分享面板要从按钮的位置弹出
    expect(sharer.origins.single, isNotNull);
    expect(sharer.origins.single!.isEmpty, isFalse);
  });

  testWidgets('群里只有自己时，页面中间的大按钮也能发邀请', (tester) async {
    final sharer = FakeSharer();
    await pumpGroup(tester, sharer: sharer);

    await tester.tap(find.text('发邀请，拉家人进来'));
    await tester.pumpAndSettle();
    expect(sharer.texts.single, GroupPage.inviteText(await GroupApi().group(7)));
  });

  testWidgets('分享面板打不开时，把邀请的话复制下来', (tester) async {
    final copied = captureClipboard(tester);
    await pumpGroup(tester, sharer: FakeSharer(opens: false));

    await tester.tap(find.text('+ 邀请'));
    await tester.pumpAndSettle();
    expect(await copied(), contains('ABCD2345'));
    expect(await copied(), contains('用邀请码加入'));
    expect(find.text('邀请的话已复制，发到微信给 TA'), findsOneWidget);
  });

  testWidgets('页面上能看到邀请码，点一下只复制邀请码', (tester) async {
    final copied = captureClipboard(tester);
    final sharer = FakeSharer();
    await pumpGroup(tester, sharer: sharer);

    await tester.tap(find.bySemanticsLabel('邀请码 ABCD2345，点一下复制'));
    await tester.pumpAndSettle();
    expect(await copied(), 'ABCD2345');
    expect(find.text('邀请码 ABCD2345 已复制'), findsOneWidget);
    expect(sharer.texts, isEmpty);
  });

  testWidgets('群里有人了就不再显示大按钮，右上角和邀请码还在', (tester) async {
    await pumpGroup(tester, sharer: FakeSharer(), members: 3);
    expect(find.text('发邀请，拉家人进来'), findsNothing);
    expect(find.text('+ 邀请'), findsOneWidget);
    expect(find.bySemanticsLabel('邀请码 ABCD2345，点一下复制'), findsOneWidget);
  });

  testWidgets('满 8 人后不能再邀请', (tester) async {
    await pumpGroup(tester, sharer: FakeSharer(), members: 8);
    expect(find.text('+ 邀请'), findsNothing);
    expect(find.text('发邀请，拉家人进来'), findsNothing);
    expect(find.bySemanticsLabel('邀请码 ABCD2345，点一下复制'), findsNothing);
  });
}
