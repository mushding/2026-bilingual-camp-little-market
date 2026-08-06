import 'package:flutter/material.dart';
import '../theme.dart';
import 'package:flutter/services.dart';
import '../services/api_client.dart';
import '../services/nfc_service.dart';
import 'roster_bind_screen.dart';
import '../widgets/amount_input_sheet.dart';

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
        SnackBar(content: Text(msg), backgroundColor: ok ? AppColors.teal : AppColors.red));
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
              style: FilledButton.styleFrom(backgroundColor: AppColors.red),
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
              color: AppColors.sky,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('當前天：${st['current_day']}', style: const TextStyle(fontSize: 16)),
                  Text('市場：${st['market_open'] == true ? '開啟' : '已關閉'}',
                      style: const TextStyle(fontSize: 16)),
                ]),
              ),
            ),
          const SizedBox(height: 16),
          const Text('換日 set_day', style: _h),
          // 換日做啥
          const Text('切換目前天數。影響各攤可用交易與『本攤位』下拉清單。每場小市集開始前切換。',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
          const Text('全體扣餐費 meal_charge_all（D2晚餐/D3午餐）', style: _h),
          const Text('不擺攤的餐：輸入單價，所有已綁卡學員一次統一扣。餘額不足者只扣到 0（餐照供）。',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _busy
                ? null
                : () async {
                    final v = await showAmountInput(context,
                        title: '全體扣餐費 — 每人扣多少？',
                        quickKeys: const [100, 150, 200],
                        min: 1,
                        hint: '例：100 → 全部人各扣 100');
                    if (v == null || !mounted) return;
                    if (await _confirm('全體扣餐費', '所有已綁卡學員每人扣 \$$v？\n餘額不足者只扣到 0。')) {
                      await _run(() => ApiClient.adminMealChargeAll(v), '全體扣餐費');
                    }
                  },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('🍱 全體扣餐費', style: TextStyle(fontSize: 16)),
            ),
          ),
          const Divider(height: 32),
          const Text('每日場控（截止/開市/5分鐘提醒）', style: _h),
          const Text('每場結束按「當日截止」凍結交易（學生才停得下來）；換日或按「重新開市」恢復。'
              '「5分鐘提醒」會讓所有關主手機跳提醒。',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () async {
                      if (await _confirm('當日截止', '凍結所有交易（不折現）。\n換日或按「重新開市」即恢復。確定？')) {
                        await _run(() => ApiClient.adminDayClose(), '當日截止');
                      }
                    },
              child: const Text('🛑 當日截止'),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => ApiClient.adminDayOpen(), '重新開市'),
              child: const Text('▶️ 重新開市'),
            ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.yellow, foregroundColor: AppColors.brown),
              onPressed: _busy
                  ? null
                  : () => _run(() => ApiClient.adminClosingSoon(), '5分鐘提醒'),
              child: const Text('⏰ 廣播 5 分鐘提醒'),
            ),
          ]),
          const Divider(height: 32),
          const Text('市場關閉 market_close（D3 突襲，不可逆）', style: _h),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
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
          const Text('全重置 reset（測試用，不可復原）', style: _h),
          const Text('學員回起始金、清空所有交易/任務/賭局/見證、天數回 D1、市場重開。保留名單與註冊。',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.paper),
            onPressed: _busy
                ? null
                : () async {
                    if (await _confirm('⚠️ 全重置',
                        '所有學員回起始金、清空所有帳本與遊戲狀態、天數回 D1、市場重開。\n保留學員名單與裝置註冊。不可復原。確定？')) {
                      await _run(() => ApiClient.adminReset(), '全重置');
                    }
                  },
            icon: const Icon(Icons.cleaning_services),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('🧹 Reset All', style: TextStyle(fontSize: 16)),
            ),
          ),
          const Divider(height: 32),
          const Text('大量綁卡（名單 → 逐人感應）', style: _h),
          const Text('名單先在 Web 後台「🪪 綁卡名單」建好，這裡點人名感應卡片綁定；NFC 不可用改掃 QR。',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const RosterBindScreen())),
            icon: const Icon(Icons.badge),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('🪪 大量綁卡', style: TextStyle(fontSize: 16)),
            ),
          ),
          const Divider(height: 32),
          const Text('讀卡 UID（綁卡/建名單用）', style: _h),
          const Text('感應 NTAG → 顯示 UID，可複製。',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
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

const _h = TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.muted);
