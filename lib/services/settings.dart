import 'package:shared_preferences/shared_preferences.dart';

/// 攤主端設定 — backend URL、本攤位、關主 UID、總控/全交易開關。
class Settings {
  Settings._();
  static final Settings instance = Settings._();

  static const _kBackendUrl = 'backend_url';
  static const _kStallId = 'stall_id';
  static const _kStaffUid = 'staff_uid';
  static const _kAdminMode = 'admin_mode';
  static const _kAllTxnMode = 'all_txn_mode';

  late SharedPreferences _prefs;

  // 預設指向正式 VM；開發/模擬器在設定畫面改成 http://10.0.2.2:8000 即可。
  String backendUrl = 'http://104.199.226.128:8080';
  String stallId = 'bank';
  String staffUid = '';
  bool adminMode = false;   // 顯示總控畫面
  bool allTxnMode = false;  // 主畫面列出全部交易（測試）

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    backendUrl = _prefs.getString(_kBackendUrl) ?? backendUrl;
    stallId = _prefs.getString(_kStallId) ?? stallId;
    staffUid = _prefs.getString(_kStaffUid) ?? staffUid;
    adminMode = _prefs.getBool(_kAdminMode) ?? adminMode;
    allTxnMode = _prefs.getBool(_kAllTxnMode) ?? allTxnMode;
  }

  Future<void> setBackendUrl(String v) async {
    backendUrl = v.trim();
    await _prefs.setString(_kBackendUrl, backendUrl);
  }

  Future<void> setStallId(String v) async {
    stallId = v.trim();
    await _prefs.setString(_kStallId, stallId);
  }

  Future<void> setStaffUid(String v) async {
    staffUid = v.trim();
    await _prefs.setString(_kStaffUid, staffUid);
  }

  Future<void> setAdminMode(bool v) async {
    adminMode = v;
    await _prefs.setBool(_kAdminMode, v);
  }

  Future<void> setAllTxnMode(bool v) async {
    allTxnMode = v;
    await _prefs.setBool(_kAllTxnMode, v);
  }
}
