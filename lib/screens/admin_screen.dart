import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/nfc_service.dart';

/// 總控管理畫面 — 換日 / 結息 / 市場關閉 / 回應卡。皆二次確認、不可逆。
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? _state;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final s = await ApiClient.adminState();
      setState(() => _state = s);
    } catch (e) {
      _snack('$e', false);
    }
  }

  void _snack(String msg, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: ok ? Colors.green : Colors.red));
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('確定執行'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _run(Future<Map<String, dynamic>> Function() fn, String label) async {
    setState(() => _busy = true);
    try {
      final r = await fn();
      _snack('$label：${r['ok'] == false ? (r['message'] ?? '失敗') : '完成 $r'}', r['ok'] != false);
      await _refresh();
    } catch (e) {
      _snack('$e', false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _state;
    return Scaffold(
      appBar: AppBar(
        title: const Text('總控管理'),
        actions: [IconButton(onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (st != null)
            Card(
              color: Colors.indigo.shade900,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('當前天：${st['current_day']}', style: const TextStyle(fontSize: 16)),
                  Text('市場：${st['market_open'] == true ? '開啟' : '已關閉'}',
                      style: const TextStyle(fontSize: 16)),
                  Text('已結息次數：${st['settlement_count']} / 3'),
                  Text('已結息天：${st['settled_days']}'),
                ]),
              ),
            ),
          const SizedBox(height: 16),
          const Text('換日 set_day', style: _h),
          Wrap(spacing: 8, children: [
            for (final d in ['D1', 'D2', 'D3'])
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        if (await _confirm('換日', '切換到 $d？')) {
                          await _run(() => ApiClient.adminSetDay(d), '換日 $d');
                        }
                      },
                child: Text(d),
              ),
          ]),
          const Divider(height: 32),
          const Text('每場結息 settle_interest（每場一次，最多 3 次）', style: _h),
          Wrap(spacing: 8, children: [
            for (final d in ['D1', 'D2', 'D3'])
              FilledButton.tonal(
                onPressed: _busy
                    ? null
                    : () async {
                        if (await _confirm('結息 $d', '對所有定存 +20%（複利）。\n每場只按一次，不可逆。確定？')) {
                          await _run(() => ApiClient.adminSettleInterest(d), '結息 $d');
                        }
                      },
                child: Text('結息 $d'),
              ),
          ]),
          const Divider(height: 32),
          const Text('市場關閉 market_close（D3 突襲，不可逆）', style: _h),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: _busy
                ? null
                : () async {
                    if (await _confirm('⚠️ 市場關閉',
                        '所有未兌換現金＋定存本利 ×0.1（銷毀 90%），市場凍結。\n只按一次、不可預告、不可逆。確定執行？')) {
                      await _run(() => ApiClient.adminMarketClose(), '市場關閉');
                    }
                  },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('🔒 市場關閉', style: TextStyle(fontSize: 18)),
            ),
          ),
          const Divider(height: 32),
          const Text('回應卡 response_card（D3，每生 +200 KP，掃卡）', style: _h),
          OutlinedButton.icon(
            onPressed: _busy ? null : _responseCard,
            icon: const Icon(Icons.nfc),
            label: const Text('掃卡登記回應卡'),
          ),
        ]),
      ),
    );
  }

  Future<void> _responseCard() async {
    final uid = await NfcService.readUidOnce();
    if (uid == null) {
      _snack('掃描取消或 NFC 不可用', false);
      return;
    }
    await _run(() => ApiClient.adminResponseCard(uid), '回應卡');
  }
}

const _h = TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70);
