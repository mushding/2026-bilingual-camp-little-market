import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 攤主端設定 — backend URL、本攤位、本機裝置 id、API token。
/// 敏感的 API token 存 Keychain/Keystore；其餘存 SharedPreferences。
class Settings {
  Settings._();
  static final Settings instance = Settings._();

  static const _kStallId = 'stall_id';
  static const _kDeviceId = 'device_id';
  static const _kScope = 'scope';
  static const _kAllTxnMode = 'all_txn_mode';
  static const _kTokenSecure = 'api_token';

  late SharedPreferences _prefs;
  final _secure = const FlutterSecureStorage();

  // 正式域名（走 Cloudflare → HTTPS）。寫死、無 setter、使用者不可改。
  // 開發/模擬器要改後端，直接改這一行（例 http://10.0.2.2:8000）後重 build。
  final String backendUrl = 'https://bilingual.smsk.church';
  String stallId = 'bank';
  // 本機自動產生的裝置 id（見證／公會完成防刷用，不需同工手動綁定）。
  String deviceId = '';
  String apiToken = '';     // Bearer，存 secure storage
  String scope = '';        // 'admin' | 'staff' | ''（未註冊）
  bool allTxnMode = false;  // 主畫面列出全部交易（測試）

  bool get isAdmin => scope == 'admin';
  bool get enrolled => apiToken.isNotEmpty;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    stallId = _prefs.getString(_kStallId) ?? stallId;
    scope = _prefs.getString(_kScope) ?? scope;
    allTxnMode = _prefs.getBool(_kAllTxnMode) ?? allTxnMode;
    apiToken = await _secure.read(key: _kTokenSecure) ?? '';
    deviceId = _prefs.getString(_kDeviceId) ?? '';
    if (deviceId.isEmpty) {
      final r = Random();
      deviceId = 'dev-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
          '-${r.nextInt(1 << 32).toRadixString(36)}';
      await _prefs.setString(_kDeviceId, deviceId);
    }
  }

  Future<void> setStallId(String v) async {
    stallId = v.trim();
    await _prefs.setString(_kStallId, stallId);
  }

  Future<void> setToken(String token, String tokenScope) async {
    apiToken = token;
    scope = tokenScope;
    await _secure.write(key: _kTokenSecure, value: token);
    await _prefs.setString(_kScope, tokenScope);
  }

  Future<void> clearToken() async {
    apiToken = '';
    scope = '';
    await _secure.delete(key: _kTokenSecure);
    await _prefs.remove(_kScope);
  }

  Future<void> setAllTxnMode(bool v) async {
    allTxnMode = v;
    await _prefs.setBool(_kAllTxnMode, v);
  }
}
