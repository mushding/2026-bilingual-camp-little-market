import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_client.dart';
import '../widgets/amount_input_sheet.dart';

/// 6 關：4 個 PK 關（贏500／輸200）+ 2 個單組別關（完成300）。2026FY主題一.docx。
enum _Mode { pk, complete }

class _Topic1Game {
  final String name;
  final _Mode mode;
  const _Topic1Game(this.name, this.mode);
}

const _kGames = [
  _Topic1Game('1. 島嶼變裝祭', _Mode.complete),
  _Topic1Game('2. 雷區大開拓', _Mode.pk),
  _Topic1Game('3. 合一傳音球', _Mode.pk),
  _Topic1Game('4. 精準連鎖', _Mode.pk),
  _Topic1Game('5. 寶藏傳聲筒', _Mode.pk),
  _Topic1Game('6. 盲眼收割者', _Mode.complete),
];

/// 主題一（Day1 大地遊戲）：以小組為單位整組加錢，不用逐一掃卡。
class Topic1Screen extends StatefulWidget {
  const Topic1Screen({super.key});
  @override
  State<Topic1Screen> createState() => _Topic1ScreenState();
}

class _Topic1ScreenState extends State<Topic1Screen> {
  List<Map<String, dynamic>> _groups = [];
  bool _loading = true;
  String? _error;
  _Topic1Game? _game;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gs = await ApiClient.topic1Groups();
      setState(() {
        _groups = gs;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _pickGroup(String group, int count) async {
    final quickKeys = switch (_game?.mode) {
      _Mode.complete => const [300],
      _Mode.pk => const [500, 200],
      null => const [200, 300, 500],
    };
    final gameSuffix = _game == null ? '' : '（${_game!.name}）';
    final amount = await showAmountInput(context,
        title: '第 $group 組（$count 人）加多少錢？$gameSuffix',
        quickKeys: quickKeys, hint: '完成300／PK贏500／PK輸200');
    if (amount == null || amount <= 0) return;
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('第 $group 組'),
        content: Text('全組 $count 人各加 \$$amount，確定？',
            style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('確認')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final res = await ApiClient.topic1Credit(
          group: group, amount: amount, gameLabel: _game?.name ?? '');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? '完成')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('主題一：大地遊戲'), actions: [
        IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
      ]),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('選關卡（可略過，只是預填金額）', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final g in _kGames)
              ChoiceChip(
                label: Text(g.name),
                selected: _game == g,
                onSelected: (v) => setState(() => _game = v ? g : null),
              ),
          ]),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          const Text('選小組（整組一次加錢）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(child: _body()),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_groups.isEmpty) return const Center(child: Text('目前查無任何小組'));
    return ListView.separated(
      itemCount: _groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final g = _groups[i];
        final group = g['group'] as String;
        final count = g['count'] as int;
        return FilledButton(
          onPressed: () => _pickGroup(group, count),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text('第 $group 組（$count 人）', style: const TextStyle(fontSize: 20)),
          ),
        );
      },
    );
  }
}
