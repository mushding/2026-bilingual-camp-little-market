import 'package:flutter/material.dart';
import '../models/student_state.dart';
import '../theme.dart';
import '../services/api_client.dart';
import '../services/nfc_service.dart';
import '../services/settings.dart';
import 'qr_scan_screen.dart';

enum _View { scan, list }

/// 小遊戲攤：預設「掃卡看狀態」給學員自助查詢；關主可切到「待完成名單」逐一標記完成。
class GuildPendingScreen extends StatefulWidget {
  final String stallId;
  final String stallLabel;
  const GuildPendingScreen({super.key, required this.stallId, required this.stallLabel});

  @override
  State<GuildPendingScreen> createState() => _GuildPendingScreenState();
}

class _GuildPendingScreenState extends State<GuildPendingScreen> {
  _View _view = _View.scan;
  bool _scanning = false;
  bool _busy = false;
  StudentState? _result;
  String? _scanErr;

  List<Map<String, dynamic>>? _pending;
  String? _listErr;

  // ── 掃卡看狀態 ──
  Future<void> _scanNfc() async {
    setState(() {
      _scanning = true;
      _result = null;
      _scanErr = null;
    });
    try {
      final uid = await NfcService.readUidOnce();
      if (uid == null) {
        setState(() {
          _scanning = false;
          _scanErr = '掃描取消或 NFC 不可用';
        });
        return;
      }
      await _lookup(uid);
    } catch (e) {
      setState(() {
        _scanning = false;
        _scanErr = '$e';
      });
    }
  }

  Future<void> _scanQr() async {
    final uid = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (uid == null) return;
    setState(() {
      _scanning = true;
      _result = null;
      _scanErr = null;
    });
    await _lookup(uid);
  }

  Future<void> _lookup(String uid) async {
    try {
      final r = await ApiClient.scan(uid: uid, stallId: widget.stallId, action: 'lookup');
      setState(() {
        _result = r;
        _scanning = false;
        _scanErr = r.ok ? null : r.message;
      });
    } catch (e) {
      setState(() {
        _scanning = false;
        _scanErr = '$e';
      });
    }
  }

  void _resetScan() => setState(() {
        _result = null;
        _scanErr = null;
      });

  Future<void> _completeHere(StudentState st) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('完成任務'),
        content: Text('${st.studentName} 完成「${widget.stallLabel}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('確認')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final res = await ApiClient.guildComplete(
        studentUid: st.uid,
        stallId: widget.stallId,
        staffUid: Settings.instance.deviceId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.message),
          backgroundColor: res.ok ? AppColors.teal : AppColors.red,
        ));
        setState(() => _result = res.ok ? res : _result);
        if (res.ok) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) _resetScan();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: AppColors.red));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── 待完成名單（關主用） ──
  Future<void> _loadList() async {
    setState(() {
      _pending = null;
      _listErr = null;
    });
    try {
      final p = await ApiClient.guildPending(widget.stallId);
      setState(() => _pending = p);
    } catch (e) {
      setState(() => _listErr = '$e');
    }
  }

  Future<void> _completeFromList(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('完成任務'),
        content: Text('${row['student_name']} 完成「${widget.stallLabel}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('確認')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final res = await ApiClient.guildComplete(
        studentUid: row['student_uid'],
        stallId: widget.stallId,
        staffUid: Settings.instance.deviceId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.message),
          backgroundColor: res.ok ? AppColors.teal : AppColors.red,
        ));
      }
      await _loadList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: AppColors.red));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchTo(_View v) {
    setState(() => _view = v);
    if (v == _View.list) _loadList();
    if (v == _View.scan) _resetScan();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.stallLabel),
        actions: [
          if (_view == _View.scan)
            IconButton(
              tooltip: '待完成名單（關主）',
              onPressed: () => _switchTo(_View.list),
              icon: const Icon(Icons.list_alt),
            )
          else
            IconButton(
              tooltip: '掃卡看狀態',
              onPressed: () => _switchTo(_View.scan),
              icon: const Icon(Icons.nfc),
            ),
        ],
      ),
      body: SafeArea(child: _view == _View.scan ? _scanBody() : _listBody()),
    );
  }

  // ── 掃卡看狀態畫面 ──
  Widget _scanBody() {
    if (_scanning && _result == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_result != null) {
      return _statusCard(_result!);
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.contactless, size: 96, color: AppColors.sage),
        const SizedBox(height: 12),
        const Text('學員感應卡片，查看目前任務狀態', style: TextStyle(fontSize: 16, color: AppColors.muted)),
        if (_scanErr != null) ...[
          const SizedBox(height: 12),
          Text(_scanErr!, style: const TextStyle(color: AppColors.red)),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _scanning ? null : _scanNfc,
          icon: const Icon(Icons.nfc),
          label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              child: Text('感應卡片', style: TextStyle(fontSize: 18))),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _scanning ? null : _scanQr,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12), child: Text('掃 QR 貼紙（NFC 備援）')),
        ),
      ]),
    );
  }

  Widget _statusCard(StudentState st) {
    final mine = st.pendingTasks.where((t) => t.gameKey == widget.stallId).toList();
    final others = st.pendingTasks.where((t) => t.gameKey != widget.stallId).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('${st.studentName}${st.group.isEmpty ? '' : '　[${st.group}]'}',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ),
          IconButton(onPressed: _resetScan, icon: const Icon(Icons.close)),
        ]),
        const Divider(height: 24),
        if (mine.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('這位學員目前沒有本關的任務', style: TextStyle(color: AppColors.muted)),
          )
        else
          for (final t in mine) _taskTile(t, highlight: true),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('其他關卡任務', style: TextStyle(fontSize: 13, color: AppColors.muted)),
          for (final t in others) _taskTile(t, highlight: false),
        ],
        const SizedBox(height: 20),
        if (mine.isNotEmpty)
          FilledButton(
            onPressed: _busy ? null : () => _completeHere(st),
            child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('完成本關任務', style: TextStyle(fontSize: 18))),
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _resetScan,
          child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12), child: Text('下一位（回感應畫面）')),
        ),
      ]),
    );
  }

  Widget _taskTile(PendingTask t, {required bool highlight}) {
    final mm = t.remainingSeconds ~/ 60, ss = t.remainingSeconds % 60;
    final urgent = t.remainingSeconds <= 120;
    return Card(
      color: highlight ? AppColors.mint : null,
      child: ListTile(
        title: Text('${t.gameName}（獎勵 ${t.reward}）'),
        trailing: Text('剩 ${mm}:${ss.toString().padLeft(2, '0')}',
            style: TextStyle(
                color: urgent ? AppColors.red : AppColors.muted,
                fontWeight: urgent ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  // ── 待完成名單畫面（關主用） ──
  Widget _listBody() {
    if (_listErr != null) {
      return Center(child: Text(_listErr!, style: const TextStyle(color: AppColors.red)));
    }
    if (_pending == null) return const Center(child: CircularProgressIndicator());
    if (_pending!.isEmpty) {
      return Column(children: [
        const Expanded(
          child: Center(
              child: Text('目前沒有派到本關的學生', style: TextStyle(color: AppColors.muted))),
        ),
        _refreshBar(),
      ]);
    }
    return Column(children: [
      Expanded(
        child: ListView.separated(
          itemCount: _pending!.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final r = _pending![i];
            final group = (r['student_group'] ?? '') as String;
            final remain = (r['remaining_seconds'] ?? 0) as int;
            final mm = remain ~/ 60, ss = remain % 60;
            final urgent = remain <= 120;
            return ListTile(
              leading: const Icon(Icons.person),
              title: Text(
                '${r['student_name'] ?? '?'}${group.isEmpty ? '' : '　[$group]'}',
                style: const TextStyle(fontSize: 18),
              ),
              subtitle: Text(
                '剩 ${mm}:${ss.toString().padLeft(2, '0')}',
                style: TextStyle(
                    color: urgent ? AppColors.red : AppColors.muted,
                    fontWeight: urgent ? FontWeight.bold : FontWeight.normal),
              ),
              trailing: FilledButton(
                onPressed: _busy ? null : () => _completeFromList(r),
                child: const Text('完成'),
              ),
            );
          },
        ),
      ),
      _refreshBar(),
    ]);
  }

  Widget _refreshBar() => Padding(
        padding: const EdgeInsets.all(8),
        child: OutlinedButton.icon(
          onPressed: _busy ? null : _loadList,
          icon: const Icon(Icons.refresh),
          label: const Text('重新整理'),
        ),
      );
}
