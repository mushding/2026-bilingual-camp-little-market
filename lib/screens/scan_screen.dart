import 'package:flutter/material.dart';
import '../data/stalls.dart';
import '../models/student_state.dart';
import '../models/txn_type.dart';
import '../services/api_client.dart';
import '../services/nfc_service.dart';
import '../services/settings.dart';
import '../widgets/amount_input_sheet.dart';
import '../widgets/exchange_picker.dart';
import '../widgets/student_card.dart';
import 'admin_screen.dart';
import 'casino_table_screen.dart';
import 'guild_pending_screen.dart';
import 'mail_screen.dart';
import 'settings_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

enum _S { idle, reading, loaded, submitting, result }

class _ScanScreenState extends State<ScanScreen> {
  _S _state = _S.idle;
  StudentState? _student;
  TxnType? _txn;
  String? _banner; // 結果訊息
  bool _bannerOk = true;

  Stall get _stall => stallById(Settings.instance.stallId);
  List<TxnType> get _allowed =>
      Settings.instance.allTxnMode ? kAllTxns : _stall.txns;

  // 特殊攤位走專屬畫面（非標準掃卡流程）
  bool get _isCasino =>
      _stall.id == 'casino_21' || _stall.id == 'casino_dice';
  bool get _isGameStall => _stall.id.startsWith('game_');
  bool get _isMail => _stall.id == 'mail';

  Future<void> _scan() async {
    setState(() {
      _state = _S.reading;
      _student = null;
      _txn = null;
      _banner = null;
    });
    try {
      final uid = await NfcService.readUidOnce();
      if (uid == null) {
        _showBanner('掃描取消或 NFC 不可用', false);
        setState(() => _state = _S.idle);
        return;
      }
      final s = await ApiClient.scan(uid: uid, stallId: _stall.id, action: 'lookup');
      setState(() {
        _student = s;
        _txn = _allowed.firstWhere((t) => t != TxnType.lookup,
            orElse: () => TxnType.lookup);
        _state = _S.loaded;
      });
      if (!s.ok) _showBanner(s.message, false);
    } catch (e) {
      _showBanner('$e', false);
      setState(() => _state = _S.idle);
    }
  }

  void _showBanner(String msg, bool ok) {
    setState(() {
      _banner = msg;
      _bannerOk = ok;
    });
  }

  void _reset() {
    setState(() {
      _state = _S.idle;
      _student = null;
      _txn = null;
    });
  }

  Future<void> _execute() async {
    final s = _student;
    final t = _txn;
    if (s == null || t == null) return;

    // 需要 input 的交易：先收 input
    int amount = 0, cost = 0, reward = 0, tier = 0;
    switch (t) {
      case TxnType.day1SellDoll:
      case TxnType.grocery:
        final v = await showAmountInput(context,
            title: '${t.label} 售價', quickKeys: const [20, 50, 100], hint: '輸入售價');
        if (v == null) return;
        amount = v;
        break;
      case TxnType.meal:
        final v = await showAmountInput(context,
            title: '餐費金額', quickKeys: const [150], min: 100, max: 250, hint: '預設 150');
        if (v == null) return;
        amount = v;
        break;
      case TxnType.day1RingToss:
        final n = await showAmountInput(context, title: '中圈數 (0–10)', max: 10, hint: '中幾圈');
        if (n == null) return;
        cost = 20;
        reward = (n < 0 ? 0 : n) * 10;
        break;
      case TxnType.day1Dart:
        final n = await showAmountInput(context, title: '命中數 (0–10)', max: 10, hint: '命中幾鏢');
        if (n == null) return;
        cost = 20;
        reward = (n < 0 ? 0 : n) * 5;
        break;
      case TxnType.day1Bingo:
        final win = await _bingoResult();
        if (win == null) return;
        cost = 20;
        reward = win ? 300 : 0;
        break;
      case TxnType.bankDeposit:
        final v = await showAmountInput(context, title: '定存金額', hint: '存多少');
        if (v == null) return;
        amount = v;
        break;
      case TxnType.bankWithdraw:
        final v = await showAmountInput(context, title: '提領金額', allowAll: true, hint: '提多少（或全部）');
        if (v == null) return;
        amount = v;
        break;
      case TxnType.donation:
        final v = await showAmountInput(context,
            title: '奉獻金額', min: 10, hint: 'D3：≥100 額外 +50 KP');
        if (v == null) return;
        amount = v;
        break;
      case TxnType.exchange:
        final v = await showExchangePicker(context);
        if (v == null) return;
        tier = v;
        break;
      case TxnType.witness:
        if (Settings.instance.staffUid.isEmpty) {
          _showBanner('請先到設定綁定關主 UID', false);
          return;
        }
        break;
      case TxnType.guildDraw:
      case TxnType.lookup:
        break;
      default:
        break;
    }

    if (!await _confirm(s, t, amount, tier)) return;

    setState(() => _state = _S.submitting);
    try {
      final res = await ApiClient.scan(
        uid: s.uid,
        stallId: _stall.id,
        action: t.action,
        amount: amount,
        cost: cost,
        reward: reward,
        tier: tier == 0 ? null : tier,
        staffUid: t == TxnType.witness ? Settings.instance.staffUid : null,
      );
      setState(() {
        _student = res;
        _state = _S.result;
      });
      _showBanner(res.message, res.ok);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _state == _S.result) _reset();
      });
    } catch (e) {
      _showBanner('$e', false);
      setState(() => _state = _S.loaded);
    }
  }

  Future<bool?> _bingoResult() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('麻將賓果結果'),
          content: const Text('任一連線即中（賠 300）'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('未中')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('中獎')),
          ],
        ),
      );

  Future<bool> _confirm(StudentState s, TxnType t, int amount, int tier) async {
    String detail = t.label;
    if (amount > 0) detail += ' \$$amount';
    if (amount == -1) detail += ' 全部';
    if (tier > 0) detail += ' 兌換檔 \$$tier';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.studentName),
        content: Text(detail, style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('確認')),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final s = Settings.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('小市集 · 攤主端'),
        actions: [
          if (s.adminMode)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AdminScreen())),
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()));
              _reset();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _stallBadge(),
              const SizedBox(height: 12),
              if (_banner != null) _bannerWidget(),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stallBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade900,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          const Icon(Icons.storefront, size: 18),
          const SizedBox(width: 8),
          Text('本攤位：${_stall.label}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (Settings.instance.allTxnMode) ...[
            const SizedBox(width: 8),
            const Text('[全交易測試]', style: TextStyle(fontSize: 12, color: Colors.amberAccent)),
          ],
        ]),
      );

  Widget _bannerWidget() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (_bannerOk ? Colors.green : Colors.red).withValues(alpha: 0.2),
          border: Border.all(color: _bannerOk ? Colors.green : Colors.red),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          Icon(_bannerOk ? Icons.check_circle : Icons.error,
              color: _bannerOk ? Colors.green : Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(_banner!, style: const TextStyle(fontSize: 15))),
        ]),
      );

  Widget _body() {
    // 特殊攤位：專屬入口
    if (_isCasino) return _entryButton('開賭桌', Icons.casino, () {
          Navigator.push(context, MaterialPageRoute(
              builder: (_) => CasinoTableScreen(table: _stall.id == 'casino_21' ? '21' : 'dice', stallId: _stall.id)));
        });
    if (_isGameStall) return _entryButton('看待完成名單', Icons.list_alt, () {
          Navigator.push(context, MaterialPageRoute(
              builder: (_) => GuildPendingScreen(stallId: _stall.id, stallLabel: _stall.label)));
        });
    if (_isMail) return _entryButton('郵政感謝卡登記', Icons.mail, () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const MailScreen()));
        });

    // 標準掃卡流程
    if (_state == _S.idle || _state == _S.reading) {
      return Column(children: [
        Expanded(
          child: Center(
            child: _state == _S.reading
                ? const Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('請靠近卡片…'),
                  ])
                : const Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.contactless, size: 96, color: Colors.white24),
                    SizedBox(height: 16),
                    Text('按「掃卡」並把卡片靠近手機背面', style: TextStyle(color: Colors.white54)),
                  ]),
          ),
        ),
        _scanButton(),
      ]);
    }

    // loaded / submitting / result
    final s = _student!;
    return Column(children: [
      StudentCard(s: s),
      const SizedBox(height: 16),
      DropdownButtonFormField<TxnType>(
        value: _txn,
        decoration: const InputDecoration(labelText: '交易類型', border: OutlineInputBorder()),
        items: _allowed
            .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
            .toList(),
        onChanged: _state == _S.submitting ? null : (v) => setState(() => _txn = v),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _state == _S.submitting ? null : _reset,
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('重新掃卡')),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: _state == _S.submitting ? null : _execute,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(_state == _S.submitting ? '處理中…' : '執 行',
                  style: const TextStyle(fontSize: 18, letterSpacing: 2)),
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _scanButton() => FilledButton.icon(
        onPressed: _state == _S.reading ? null : _scan,
        icon: const Icon(Icons.nfc, size: 28),
        label: const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Text('掃 卡', style: TextStyle(fontSize: 22, letterSpacing: 4)),
        ),
      );

  Widget _entryButton(String label, IconData icon, VoidCallback onTap) => Center(
        child: FilledButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 28),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            child: Text(label, style: const TextStyle(fontSize: 20)),
          ),
        ),
      );
}
