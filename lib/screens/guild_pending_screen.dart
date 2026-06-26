import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/settings.dart';

/// 小遊戲攤：列出派到本關的 pending 學生 → 點「完成」固定獎勵。
class GuildPendingScreen extends StatefulWidget {
  final String stallId;
  final String stallLabel;
  const GuildPendingScreen({super.key, required this.stallId, required this.stallLabel});

  @override
  State<GuildPendingScreen> createState() => _GuildPendingScreenState();
}

class _GuildPendingScreenState extends State<GuildPendingScreen> {
  List<Map<String, dynamic>>? _pending;
  String? _err;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _pending = null;
      _err = null;
    });
    try {
      final p = await ApiClient.guildPending(widget.stallId);
      setState(() => _pending = p);
    } catch (e) {
      setState(() => _err = '$e');
    }
  }

  Future<void> _complete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('完成任務'),
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
        staffUid: Settings.instance.staffUid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.message),
          backgroundColor: res.ok ? Colors.green : Colors.red,
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.stallLabel} · 待完成'),
        actions: [IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      body: SafeArea(child: _content()),
    );
  }

  Widget _content() {
    if (_err != null) {
      return Center(child: Text(_err!, style: const TextStyle(color: Colors.red)));
    }
    if (_pending == null) return const Center(child: CircularProgressIndicator());
    if (_pending!.isEmpty) {
      return const Center(child: Text('目前沒有派到本關的學生', style: TextStyle(color: Colors.white54)));
    }
    return ListView.separated(
      itemCount: _pending!.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final r = _pending![i];
        return ListTile(
          leading: const Icon(Icons.person),
          title: Text(r['student_name'] ?? '?', style: const TextStyle(fontSize: 18)),
          subtitle: Text('抽於 ${r['drawn_at'] ?? ''}'),
          trailing: FilledButton(
            onPressed: _busy ? null : () => _complete(r),
            child: const Text('完成'),
          ),
        );
      },
    );
  }
}
