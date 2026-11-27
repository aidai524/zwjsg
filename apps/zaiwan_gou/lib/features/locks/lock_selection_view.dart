import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// iOS：限时里选了哪些 App 和类别。图标和名字由系统画
/// （ios/Runner/ScreenTimePlugin.swift 的 SelectionChips），Flutter 拿不到名字。
/// 一行一个，最多 [maxRows] 行，多的写“还有 N 个”（2026-11-27：横着一排小标签时，系统画的名字只露出半个字）。
/// 高度按选了几个算：Flutter 得先定好平台视图的高，行高、行距和 SelectionChips 一致
class LockSelectionView extends StatelessWidget {
  const LockSelectionView({super.key, this.lockId, this.draft = false, this.count = 1});

  /// 已保存的锁
  final String? lockId;

  /// true：显示刚选好、还没保存的
  final bool draft;

  /// 选了几个（App、类别、网站加起来）
  final int count;

  static const maxRows = 3;
  static const rowHeight = 34.0;
  static const spacing = 4.0;
  static const moreHeight = 18.0;

  static double heightFor(int count) {
    final rows = count.clamp(1, maxRows);
    var height = rows * rowHeight + (rows - 1) * spacing;
    if (count > maxRows) height += spacing + moreHeight;
    return height;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: heightFor(count),
      child: UiKitView(
        viewType: 'zwjsg/lock_selection',
        creationParams: {'lockId': lockId, 'draft': draft},
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}
