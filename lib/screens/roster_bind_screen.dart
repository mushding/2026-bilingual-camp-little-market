import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_client.dart';
import '../services/nfc_service.dart';
import 'qr_scan_screen.dart';

/// 大量綁卡 — 名單（Web 後台預先建好）逐人綁 NTAG 卡。
/// 點人名 → NFC 感應；右側 QR 鈕 → 掃卡片 QR 貼紙（NFC 不可用時）。
class RosterBindScreen extends StatefulWidget {
  const RosterBindScreen({super.key});
  @override
  State<RosterBindScreen> createState() => _RosterBindScreenState();
}

class _RosterBindScreenState extends State<RosterBindScreen> {
  Map<String, dynamic>? _roster;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final r = await ApiClient.rosterList();
      if (mounted) setState(() => _roster = r);
    } catch (e) {
      _snack('$e', false);
    }
  }

  void _snack(String msg, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: ok ? AppColors.teal : AppColors.red));
  }

  Future<void> _bind(Map<String, dynamic> entry, {required bool useQr}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      String? uid;
      if (useQr) {
        uid = await Navigator.push<String>(
            context, MaterialPageRoute(builder: (_) => const QrScanScreen()));
      } else {
        _snack('感應中…請把 ${entry['name']} 的卡靠近手機', true);
        uid = await NfcService.readUidOnce();
      }
      if (uid == null || uid.isEmpty) {
        _snack('掃描取消或讀不到卡', false);
        return;
      }
      final r = await ApiClient.rosterBind(uid: entry['uid'] as String, cardUid: uid);
      _snack(r['ok'] == true ? '✅ ${entry['name']} 綁定 $uid' : '${r['message']}',
          r['ok'] == true);
      await _refresh();
    } catch (e) {
      _snack('$e', false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _roster;
    final entries = (r?['entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    // 依組別分段
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final e in entries) {
      final g = (e['group'] as String?)?.isNotEmpty == true ? e['group'] as String : '（未分組）';
      groups.putIfAbsent(g, () => []).add(e);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(r == null ? '大量綁卡' : '大量綁卡 ${r['bound']}/${r['total']}'),
        actions: [IconButton(onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: r == null
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
              ? const Center(child: Text('名單是空的\n先到 Web 後台「🪪 綁卡名單」新增名單', textAlign: TextAlign.center))
              : ListView(children: [
                  for (final g in groups.entries) ...[
                    Container(
                      color: AppColors.mint,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                          '${g.key}　${g.value.where((e) => e['bound'] == true).length}/${g.value.length} 已綁',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    for (final e in g.value)
                      ListTile(
                        enabled: !_busy,
                        leading: Text(e['bound'] == true ? '✅' : '❌',
                            style: const TextStyle(fontSize: 20)),
                        title: Text('${e['name']}'
                            '${(e['seat_no'] as String?)?.isNotEmpty == true ? '（${e['seat_no']}）' : ''}'),
                        subtitle: e['bound'] == true
                            ? Text('${e['card_uid']}',
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 12))
                            : const Text('點我感應綁卡', style: TextStyle(color: AppColors.brown)),
                        trailing: e['bound'] == true
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.qr_code_scanner),
                                tooltip: '掃 QR 綁卡',
                                onPressed: _busy ? null : () => _bind(e, useQr: true),
                              ),
                        onTap: e['bound'] == true ? null : () => _bind(e, useQr: false),
                      ),
                  ],
                ]),
    );
  }
}
