import 'package:flutter_test/flutter_test.dart';
import 'package:series_share/series_share.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('分享面板打不开（这里没有分享插件）时返回 false，不抛异常，调用方好走备用办法', () async {
    expect(await const SystemTextSharer().share('来关心群'), isFalse);
  });
}
