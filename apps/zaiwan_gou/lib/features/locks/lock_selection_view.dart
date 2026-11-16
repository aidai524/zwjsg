import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// iOS：时间锁里选了哪些 App 和类别。图标和名字由系统画
/// （ios/Runner/ScreenTimePlugin.swift 的 LockSelectionFactory），Flutter 拿不到名字。
class LockSelectionView extends StatelessWidget {
  const LockSelectionView({super.key, this.lockId, this.draft = false});

  /// 已保存的锁
  final String? lockId;

  /// true：显示刚选好、还没保存的
  final bool draft;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: UiKitView(
        viewType: 'zwjsg/lock_selection',
        creationParams: {'lockId': lockId, 'draft': draft},
        creationParamsCodec: const StandardMessageCodec(),
        // 标签多了会横着滚
        gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => HorizontalDragGestureRecognizer())},
      ),
    );
  }
}
