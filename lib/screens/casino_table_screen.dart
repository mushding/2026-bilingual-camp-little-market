import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/nfc_service.dart';
import '../widgets/amount_input_sheet.dart';

/// 賭場多步驟桌：開局 → 湊桌下注 → 封盤結算 → 結果。
/// table = '21' | 'dice'。
class CasinoTableScreen extends StatefulWidget {
  final String table;
  final String stallId;
  const CasinoTableScreen({super.key, required this.table, required this.stallId});

  @override
  State<CasinoTableScreen> createState() => _CasinoTableScreenState();
}

enum _Phase { idle, collect, resolve, result }

class _CasinoTableScreenState extends State<CasinoTableScreen> {
  _Phase _phase = _Phase.idle;
  int? _roundId;
  List<Map<String, dynamic>> _bets = []; // {uid,name,bet_type,amount}
  List<Map<String, dynamic>> _results = [];
  int _d1 = 1, _d2 = 1;
  final Map<String, bool> _wins = {}; // 21: uid -> win
  bool _busy = false;
  bool _scanning = false;  // NFC session 開著（讓按鈕顯示「感應中…」）

  bool get _isDice => widget.table == 'dice';

  void _snack(String m, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), backgroundColor: ok ? Colors.green : Colors.red));
  }

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      final r = await ApiClient.casinoOpen(widget.table, widget.stallId);
      if (r['ok'] != true) {
        _snack(r['message'] ?? '開局失敗', false);
        return;
      }
      setState(() {
        _roundId = r['round_id'];
        _bets = [];
        _results = [];
        _wins.clear();
        _phase = _Phase.collect;
      });
    } catch (e) {
      _snack('$e', false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPlayer() async {
    setState(() => _scanning = true);
    final uid = await NfcService.readUidOnce();
    if (mounted) setState(() => _scanning = false);
    if (uid == null) return;

    String betType = '21:play';
    if (_isDice) {
      final t = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) {
          Widget option(String value, String title, String subtitle, String payout) =>
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                title: Text(title,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold)),
                subtitle: Text(subtitle, style: const TextStyle(fontSize: 16)),
                trailing: Text(payout, style: const TextStyle(fontSize: 18)),
                onTap: () => Navigator.pop(ctx, value),
              );
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('壓注內容',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                option('big', '大', '和 8–12', '賠 1:1'),
                option('small', '小', '和 2–6', '賠 1:1'),
                option('seven', '七', '和 = 7', '賠 4:1'),
              ],
            ),
          );
        },
      );
      if (t == null) return;
      betType = t;
    }
    final amt = await showAmountInput(context,
        title: '壓注金額 (10–100)', quickKeys: const [10, 20, 50, 100], min: 10, max: 100);
    if (amt == null) return;

    setState(() => _busy = true);
    try {
      final r = await ApiClient.casinoBet(
          roundId: _roundId!, uid: uid, betType: betType, amount: amt);
      if (r['ok'] != true) {
        _snack(r['message'] ?? '下注失敗', false);
        return;
      }
      setState(() => _bets = (r['table_bets'] as List).cast<Map<String, dynamic>>());
    } catch (e) {
      _snack('$e', false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(String uid) async {
    setState(() => _busy = true);
    try {
      final r = await ApiClient.casinoCancel(_roundId!, uid);
      if (r['ok'] == true) {
        setState(() => _bets = (r['table_bets'] as List).cast<Map<String, dynamic>>());
      } else {
        _snack(r['message'] ?? '取消失敗', false);
      }
    } catch (e) {
      _snack('$e', false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _settle() async {
    setState(() => _busy = true);
    try {
      final r = _isDice
          ? await ApiClient.casinoSettleDice(_roundId!, [_d1, _d2])
          : await ApiClient.casinoSettle21(
              _roundId!,
              _bets.map((b) => {'uid': b['uid'], 'win': _wins[b['uid']] ?? false}).toList());
      if (r['ok'] != true) {
        _snack(r['message'] ?? '結算失敗', false);
        return;
      }
      setState(() {
        _results = (r['results'] as List).cast<Map<String, dynamic>>();
        _phase = _Phase.result;
      });
    } catch (e) {
      _snack('$e', false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('賭場 · ${_isDice ? "大小骰子" : "21點"}')),
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: _content())),
    );
  }

  Widget _content() {
    switch (_phase) {
      case _Phase.idle:
        return Center(
          child: FilledButton.icon(
            onPressed: _busy ? null : _open,
            icon: const Icon(Icons.add),
            label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                child: Text('開新局', style: TextStyle(fontSize: 20))),
          ),
        );
      case _Phase.collect:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Round #$_roundId · 已入座 ${_bets.length}/6'),
          const SizedBox(height: 8),
          Expanded(child: _betList(cancelable: true)),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || _scanning || _bets.length >= 6 ? null : _addPlayer,
                icon: _scanning
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.nfc),
                label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_scanning ? '感應中…請靠近卡片' : '感應加人')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _busy || _bets.isEmpty ? null : () => setState(() => _phase = _Phase.resolve),
                child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12), child: Text('封盤')),
              ),
            ),
          ]),
        ]);
      case _Phase.resolve:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _isDice ? _diceResolve() : _resolve21()),
          FilledButton(
            onPressed: _busy ? null : _settle,
            child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('結算', style: TextStyle(fontSize: 18))),
          ),
        ]);
      case _Phase.result:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: ListView(children: [
              for (final r in _results)
                Card(
                  child: ListTile(
                    title: Text(r['name'] ?? '?'),
                    subtitle: Text('注：${r['bet']}'),
                    trailing: Text(
                      '${(r['delta'] as int) >= 0 ? '+' : ''}${r['delta']}　餘 \$${r['balance']}',
                      style: TextStyle(
                          fontSize: 16,
                          color: (r['delta'] as int) >= 0 ? Colors.greenAccent : Colors.redAccent),
                    ),
                  ),
                ),
            ]),
          ),
          FilledButton(
            onPressed: () => setState(() => _phase = _Phase.idle),
            child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14), child: Text('結束本局')),
          ),
        ]);
    }
  }

  Widget _betList({bool cancelable = false}) {
    if (_bets.isEmpty) {
      return const Center(child: Text('感應學生卡加入桌面', style: TextStyle(color: Colors.white54)));
    }
    return ListView(children: [
      for (final b in _bets)
        Card(
          child: ListTile(
            title: Text(b['name'] ?? '?'),
            subtitle: Text('${b['bet_type']} · \$${b['amount']}'),
            trailing: cancelable
                ? IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.redAccent),
                    onPressed: _busy ? null : () => _cancel(b['uid']))
                : null,
          ),
        ),
    ]);
  }

  Widget _diceResolve() => Column(children: [
        const Text('輸入兩顆骰點數', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _diceStepper(_d1, (v) => setState(() => _d1 = v)),
          _diceStepper(_d2, (v) => setState(() => _d2 = v)),
        ]),
        const SizedBox(height: 16),
        Text('和 = ${_d1 + _d2}　→ ${_diceLabel(_d1 + _d2)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Divider(height: 32),
        Expanded(child: _betList()),
      ]);

  String _diceLabel(int s) => s == 7 ? '七' : (s <= 6 ? '小' : '大');

  Widget _diceStepper(int v, ValueChanged<int> onChange) => Column(children: [
        Text('$v', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
        Row(children: [
          IconButton(
              onPressed: v > 1 ? () => onChange(v - 1) : null,
              icon: const Icon(Icons.remove_circle, size: 32)),
          IconButton(
              onPressed: v < 6 ? () => onChange(v + 1) : null,
              icon: const Icon(Icons.add_circle, size: 32)),
        ]),
      ]);

  Widget _resolve21() => Column(children: [
        const Text('逐人標記贏／輸（平手歸莊＝輸）', style: TextStyle(fontSize: 15)),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(children: [
            for (final b in _bets)
              SwitchListTile(
                title: Text(b['name'] ?? '?'),
                subtitle: Text('\$${b['amount']}　${(_wins[b['uid']] ?? false) ? "贏" : "輸"}'),
                value: _wins[b['uid']] ?? false,
                onChanged: (v) => setState(() => _wins[b['uid']] = v),
              ),
          ]),
        ),
      ]);
}
