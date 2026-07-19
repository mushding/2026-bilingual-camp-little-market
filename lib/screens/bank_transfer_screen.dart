import 'package:flutter/material.dart';
import '../models/student_state.dart';
import '../services/api_client.dart';
import '../services/nfc_service.dart';
import '../widgets/amount_input_sheet.dart';

/// 銀行服務三：轉帳。感應 A 卡 → 輸入金額 → 感應 B 卡 → 確認送出。
/// 無手續費、無金額上限；市場關閉後不可轉（跟其他資金操作一致）。
class BankTransferScreen extends StatefulWidget {
  const BankTransferScreen({super.key});
  @override
  State<BankTransferScreen> createState() => _BankTransferScreenState();
}

enum _Step { scanFrom, scanTo, busy, done }

class _BankTransferScreenState extends State<BankTransferScreen> {
  _Step _step = _Step.scanFrom;
  StudentState? _from;
  String? _fromUid;
  int _amount = 0;
  String? _msg;
  bool _msgOk = true;

  Future<void> _scanFrom() async {
    setState(() => _step = _Step.busy);
    final uid = await NfcService.readUidOnce();
    if (uid == null) {
      setState(() => _step = _Step.scanFrom);
      return;
    }
    final s = await ApiClient.scan(uid: uid, stallId: 'bank', action: 'lookup');
    if (!s.ok) {
      setState(() {
        _msg = s.message;
        _msgOk = false;
        _step = _Step.scanFrom;
      });
      return;
    }
    final amt = await showAmountInput(context,
        title: '${s.studentName} 要轉出多少？', hint: '目前餘額 \$${s.balance}');
    if (amt == null) {
      setState(() => _step = _Step.scanFrom);
      return;
    }
    setState(() {
      _from = s;
      _fromUid = uid;
      _amount = amt;
      _msg = null;
      _step = _Step.scanTo;
    });
  }

  Future<void> _scanTo() async {
    setState(() => _step = _Step.busy);
    final uid = await NfcService.readUidOnce();
    if (uid == null) {
      setState(() => _step = _Step.scanTo);
      return;
    }
    if (uid == _fromUid) {
      setState(() {
        _msg = '不能轉給自己，請感應另一位學生的卡';
        _msgOk = false;
        _step = _Step.scanTo;
      });
      return;
    }
    final to = await ApiClient.scan(uid: uid, stallId: 'bank', action: 'lookup');
    if (!to.ok) {
      setState(() {
        _msg = to.message;
        _msgOk = false;
        _step = _Step.scanTo;
      });
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確認轉帳'),
        content: Text('${_from!.studentName} → ${to.studentName}\n金額 \$$_amount',
            style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('確認轉帳')),
        ],
      ),
    );
    if (ok != true) {
      setState(() => _step = _Step.scanTo);
      return;
    }
    try {
      final res = await ApiClient.bankTransfer(fromUid: _fromUid!, toUid: uid, amount: _amount);
      setState(() {
        _msg = res['ok'] == true
            ? '✅ 轉帳成功：${_from!.studentName} → ${to.studentName} \$$_amount'
            : (res['message'] ?? '轉帳失敗').toString();
        _msgOk = res['ok'] == true;
        _step = _Step.done;
      });
    } catch (e) {
      setState(() {
        _msg = '$e';
        _msgOk = false;
        _step = _Step.scanTo;
      });
    }
  }

  void _reset() {
    setState(() {
      _from = null;
      _fromUid = null;
      _amount = 0;
      _msg = null;
      _step = _Step.scanFrom;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('銀行 · 轉帳')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_msg != null) _banner(),
            Expanded(child: Center(child: _body())),
          ]),
        ),
      ),
    );
  }

  Widget _banner() {
    final c = _msgOk ? Colors.green : Colors.red;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.2),
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(_msg!, style: const TextStyle(fontSize: 15)),
    );
  }

  Widget _body() {
    switch (_step) {
      case _Step.busy:
        return const Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('請靠近卡片…'),
        ]);
      case _Step.scanFrom:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.contactless, size: 96, color: Colors.white24),
          const SizedBox(height: 16),
          const Text('步驟 1／2：感應「轉出」學生的卡', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _scanFrom,
            icon: const Icon(Icons.nfc, size: 28),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              child: Text('掃卡（轉出方）', style: TextStyle(fontSize: 20)),
            ),
          ),
        ]);
      case _Step.scanTo:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${_from!.studentName} 轉出 \$$_amount',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Icon(Icons.contactless, size: 96, color: Colors.white24),
          const SizedBox(height: 16),
          const Text('步驟 2／2：感應「轉入」學生的卡', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _scanTo,
            icon: const Icon(Icons.nfc, size: 28),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              child: Text('掃卡（轉入方）', style: TextStyle(fontSize: 20)),
            ),
          ),
        ]);
      case _Step.done:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle, size: 72, color: Colors.green),
          const SizedBox(height: 16),
          FilledButton(onPressed: _reset, child: const Text('再轉一筆')),
        ]);
    }
  }
}
