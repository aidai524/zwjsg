import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 系列 App 共用的开源许可页（2026-11-26，狗 App“我的 › 开源许可”、天气 App“设置 › 开源许可”）：
/// 用 Flutter 自带的 LicensePage，头上是 App 名、图标和版本。
/// Dart 包的许可 Flutter 自己列；Dart 包以外、打包进 App 的模型、字体、素材，由各 App 在 main() 里
/// 用 LicenseRegistry.addLicense 补上（狗 App 见 lib/core/licenses.dart）。
/// App 都没接系统的中文本地化，这一页的标题、“N 份许可”、返回键的提示换成中文（“Powered by Flutter”是 Flutter 写死的）
Future<void> showPopLicenses(
  BuildContext context, {
  required String appName,
  required String version,
  String? iconAsset,
  String legalese = 'App 里用到的开源软件，以及它们的许可证',
}) {
  return Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
    builder: (context) => Localizations.override(
      context: context,
      delegates: const [_LicenseTexts.delegate],
      child: LicensePage(
        applicationName: appName,
        applicationVersion: version,
        applicationIcon: iconAsset == null
            ? null
            : Padding(
                padding: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(iconAsset, width: 64, height: 64),
                ),
              ),
        applicationLegalese: legalese,
      ),
    ),
  ));
}

/// 许可页上用到的几处系统文字，换成中文
class _LicenseTexts extends DefaultMaterialLocalizations {
  const _LicenseTexts();

  static const LocalizationsDelegate<MaterialLocalizations> delegate = _LicenseTextsDelegate();

  @override
  String get licensesPageTitle => '开源许可';

  @override
  String licensesPackageDetailText(int licenseCount) => '$licenseCount 份许可';

  @override
  String get backButtonTooltip => '返回';
}

class _LicenseTextsDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _LicenseTextsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) => SynchronousFuture(const _LicenseTexts());

  @override
  bool shouldReload(_LicenseTextsDelegate old) => false;
}
