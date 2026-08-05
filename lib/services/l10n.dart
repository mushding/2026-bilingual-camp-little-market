import 'dart:ui';

/// 極簡雙語：系統語言是中文 → 中文，其它 → 英文。
/// 用法：L10n.t('中文', 'English')。
class L10n {
  L10n._();
  static final bool isEn =
      PlatformDispatcher.instance.locale.languageCode != 'zh';
  static String t(String zh, String en) => isEn ? en : zh;
}
