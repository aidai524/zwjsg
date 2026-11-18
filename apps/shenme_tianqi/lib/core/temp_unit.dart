/// 温度单位。数据源和服务端给的数字一律是摄氏度（数字照搬数据源），App 显示时再换算；
/// 服务端拼好的句子（秋裤理由、关心群的一句事实、早安推送）按请求里带的单位写。
/// 换算方法和服务端的 app/Support/TempUnit.php 保持一致：四舍五入到整数。
enum TempUnit {
  celsius('c', '摄氏度 ℃'),
  fahrenheit('f', '华氏度 ℉');

  const TempUnit(this.key, this.label);

  /// 接口和手机上存的值
  final String key;

  /// 设置页上显示的名字
  final String label;

  static TempUnit fromKey(String? key) => key == fahrenheit.key ? fahrenheit : celsius;

  /// 摄氏度换成这个单位，四舍五入到整数
  int convert(int c) => this == TempUnit.celsius ? c : (c * 9 / 5 + 32).round();

  /// 显示用，例如“23°”
  String deg(int c) => '${convert(c)}°';
}
