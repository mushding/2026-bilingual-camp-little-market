import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_client.dart';
import '../services/nfc_service.dart';

/// 總控管理畫面 — 換日 / 結息 / 市場關閉。皆二次確認、不可逆。
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? _state;
  bool _busy = false;
  bool _scanning = false;

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

  Future<void> _readUid() async {
    setState(() => _scanning = true);
    final uid = await NfcService.readUidOnce();
    if (!mounted) return;
    setState(() => _scanning = false);
    if (uid == null) {
      _snack('掃描取消或 NFC 不可用', false);
      return;
    }
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('卡片 UID'),
        content: SelectableText(uid,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 22)),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: uid));
              _snack('已複製 UID', true);
            },
            child: const Text('複製'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉')),
        ],
      ),
    );
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
          // 換日做啥
          const Text('切換目前天數。影響各攤可用交易與『本攤位』下拉清單，並決定結息屬於哪一場。每場小市集開始前切換。',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
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
              // 已結息過就 disable + 打勾
              if ((_state?['settled_days'] as List?)?.contains(d) == true)
                FilledButton.tonal(onPressed: null, child: Text('結息 $d ✓'))
              else
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
          const Text('讀卡 UID（綁卡/建名單用）', style: _h),
          const Text('感應 NTAG → 顯示 UID，可複製。',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy || _scanning ? null : _readUid,
            icon: _scanning
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.nfc),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(_scanning ? '感應中…請靠近卡片' : '掃卡讀 UID',
                  style: const TextStyle(fontSize: 16)),
            ),
          ),
        ]),
      ),
    );
  }
}

const _h = TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70);
