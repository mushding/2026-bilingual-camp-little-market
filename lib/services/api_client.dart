import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/student_state.dart';
import 'settings.dart';

/// Backend API client。所有方法 5s timeout、非 200 throw。
class ApiClient {
  static Uri _u(String path) => Uri.parse('${Settings.instance.backendUrl}$path');
  static const _h = {'Content-Type': 'application/json'};
  static const _t = Duration(seconds: 5);

  static Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final res = await http.post(_u(path), headers: _h, body: jsonEncode(body)).timeout(_t);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<dynamic> _get(String path) async {
    final res = await http.get(_u(path), headers: _h).timeout(_t);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body);
  }

  // ── 單學生交易 ───────────────────────────────────────────────────────
  static Future<StudentState> scan({
    required String uid,
    required String stallId,
    String action = 'lookup',
    int amount = 0,
    int cost = 0,
    int reward = 0,
    int? tier,
    int cards = 0,
    String? senderName,
    String? staffUid,
  }) async {
    final body = <String, dynamic>{
      'uid': uid,
      'stall_id': stallId,
      'action': action,
      'amount': amount,
      'cost': cost,
      'reward': reward,
      'cards': cards,
    };
    if (tier != null) body['tier'] = tier;
    if (senderName != null) body['sender_name'] = senderName;
    if (staffUid != null && staffUid.isNotEmpty) body['staff_uid'] = staffUid;
    return StudentState.fromJson(await _post('/api/scan', body));
  }

  // ── 郵政 by-name 反查 ────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> studentSearch(String name) async {
    final r = await _get('/api/students/search?name=${Uri.encodeQueryComponent(name)}');
    return (r as List).cast<Map<String, dynamic>>();
  }

  // ── 公會 ──────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> guildPending(String stallId) async {
    final r = await _get('/api/guild/pending?stall_id=$stallId');
    return (r as List).cast<Map<String, dynamic>>();
  }

  static Future<StudentState> guildComplete({
    required String studentUid,
    required String stallId,
    String? staffUid,
  }) async {
    return StudentState.fromJson(await _post('/api/guild/complete', {
      'student_uid': studentUid,
      'stall_id': stallId,
      if (staffUid != null && staffUid.isNotEmpty) 'staff_uid': staffUid,
    }));
  }

  // ── 賭場 ──────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> casinoOpen(String table, String stallId) =>
      _post('/api/casino/open', {'table': table, 'stall_id': stallId});

  static Future<Map<String, dynamic>> casinoBet({
    required int roundId,
    required String uid,
    required String betType,
    required int amount,
  }) =>
      _post('/api/casino/bet',
          {'round_id': roundId, 'uid': uid, 'bet_type': betType, 'amount': amount});

  static Future<Map<String, dynamic>> casinoCancel(int roundId, String uid) =>
      _post('/api/casino/cancel', {'round_id': roundId, 'uid': uid});

  static Future<Map<String, dynamic>> casinoSettleDice(int roundId, List<int> dice) =>
      _post('/api/casino/settle', {'round_id': roundId, 'dice': dice});

  static Future<Map<String, dynamic>> casinoSettle21(
          int roundId, List<Map<String, dynamic>> results) =>
      _post('/api/casino/settle', {'round_id': roundId, 'results': results});

  static Future<Map<String, dynamic>> casinoRound(int roundId) async =>
      await _get('/api/casino/round/$roundId') as Map<String, dynamic>;

  // ── 管理（總控） ──────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> adminSetDay(String day) =>
      _post('/api/admin/set_day', {'day': day});

  static Future<Map<String, dynamic>> adminSettleInterest(String day) =>
      _post('/api/admin/settle_interest', {'day': day});

  static Future<Map<String, dynamic>> adminMarketClose() =>
      _post('/api/admin/market_close', {});

  static Future<Map<String, dynamic>> adminResponseCard(String uid) =>
      _post('/api/admin/response_card', {'uid': uid});

  static Future<Map<String, dynamic>> adminState() async =>
      await _get('/api/admin/state') as Map<String, dynamic>;

  static Future<Map<String, dynamic>> adminBind({
    required String uid,
    required String name,
    required int seedAmount,
  }) =>
      _post('/api/admin/bind', {'uid': uid, 'name': name, 'seed_amount': seedAmount});
}
