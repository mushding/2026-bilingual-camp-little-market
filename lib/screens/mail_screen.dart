import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../widgets/amount_input_sheet.dart';

/// 郵政感謝卡登記（唯一非 NFC by-name 流程）。
/// 輸入寄件人名字 → 候選清單（同名以小組/座號消歧）→ 選定 → 卡數 → +20×n KP。
class MailScreen extends StatefulWidget {
  const MailScreen({super.key});
  @override
  State<MailScreen> createState() => _MailScreenState();
}

class _MailScreenState extends State<MailScreen> {
  final _name = TextEditingController();
  List<Map<String, dynamic>>? _candidates;
  bool _busy = false;

  Future<void> _search() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _busy = true;
      _candidates = null;
    });
    try {
      final c = await ApiClient.studentSearch(name);
      setState(() => _candidates = c);
      if (c.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('查無此寄件人（卡上需寫名字）')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register(Map<String, dynamic> stu) async {
    final cards = await showAmountInput(context,
        title: '${stu['name']} — 感謝卡張數', quickKeys: const [1, 2, 3, 5, 10], min: 1, hint: '張數不限');
    if (cards == null) return;
    setState(() => _busy = true);
    try {
      final res = await ApiClient.scan(
          uid: stu['uid'], stallId: 'mail', action: 'mail_kp', cards: cards);
      if (mounted) {
        if (res.ok) {
          _name.clear();
          setState(() => _candidates = null);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ ${res.message}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res.message),
            backgroundColor: Colors.red,
          ));
        }
      }
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
      appBar: AppBar(title: const Text('郵政 · 感謝卡登記')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '卡上寄件人名字',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _busy ? null : _search, child: const Text('搜尋')),
            ]),
            const SizedBox(height: 8),
            const Text('紙本卡無 UID，依名字反查（可打部分字）；同名請以小組/座號核對選對人',
                style: TextStyle(fontSize: 12, color: Colors.white38)),
            const SizedBox(height: 12),
            Expanded(child: _list()),
          ]),
        ),
      ),
    );
  }

  Widget _list() {
    if (_busy && _candidates == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_candidates == null) {
      return const Center(child: Text('輸入名字後搜尋', style: TextStyle(color: Colors.white54)));
    }
    return ListView.separated(
      itemCount: _candidates!.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final c = _candidates![i];
        final dis = [c['group'], c['seat_no']].where((x) => x != null).join(' · ');
        return ListTile(
          title: Text(c['name'] ?? '?', style: const TextStyle(fontSize: 18)),
          subtitle: Text(dis.isEmpty ? c['uid'] : dis),
          trailing: const Icon(Icons.add_card),
          onTap: _busy ? null : () => _register(c),
        );
      },
    );
  }
}
