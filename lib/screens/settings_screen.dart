import 'package:flutter/material.dart';
import '../data/stalls.dart';
import '../services/api_client.dart';
import '../services/settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _code = TextEditingController();
  late String _stallId;
  bool _enrolling = false;
  String _day = '';  // 目前天（後端），用來過濾攤位下拉

  @override
  void initState() {
    super.initState();
    _stallId = Settings.instance.stallId;
    _loadDay();
  }

  Future<void> _loadDay() async {
    if (!Settings.instance.enrolled) return;  // 未註冊無法呼叫 API
    try {
      final st = await ApiClient.appState();
      if (mounted) setState(() => _day = st['current_day'] ?? '');
    } catch (_) {/* 取不到就顯示全部攤位 */}
  }

  /// 依目前天過濾攤位；取不到天則顯示全部。
  List<Stall> get _stallOptions =>
      _day.isEmpty ? kStalls : stallsForDay(_day);

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _snack(String m, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), backgroundColor: ok ? Colors.green : Colors.red));
  }

  Future<void> _enroll() async {
    setState(() => _enrolling = true);
    try {
      final scope = await ApiClient.enroll(_code.text.trim(),
          label: stallById(_stallId).label);
      _code.clear();
      _snack('註冊成功（權限：$scope）', true);
      setState(() {});
    } catch (e) {
      _snack('$e', false);
    } finally {
      if (mounted) setState(() => _enrolling = false);
    }
  }

  Future<void> _unenroll() async {
    await Settings.instance.clearToken();
    _snack('已清除本機 token', true);
    setState(() {});
  }

  Future<void> _save() async {
    await Settings.instance.setStallId(_stallId);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = Settings.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── 裝置註冊 ──
            Card(
              color: s.enrolled ? Colors.green.shade900 : Colors.orange.shade900,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(s.enrolled ? Icons.verified_user : Icons.gpp_maybe),
                    const SizedBox(width: 8),
                    Text(s.enrolled ? '已註冊（權限：${s.scope}）' : '尚未註冊裝置',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 8),
                  if (!s.enrolled) ...[
                    TextField(
                      controller: _code,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: '設定碼（總控發給你）',
                        hintText: 'FYstaff-... / FYadmin-...',
                        border: OutlineInputBorder(),
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _enrolling ? null : _enroll,
                      icon: const Icon(Icons.key),
                      label: Text(_enrolling ? '註冊中…' : '註冊此裝置'),
                    ),
                  ] else
                    OutlinedButton.icon(
                      onPressed: _unenroll,
                      icon: const Icon(Icons.logout),
                      label: const Text('清除 token（換手機/重註冊）'),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 20),

            Text(_day.isEmpty ? '本攤位' : '本攤位（目前 $_day 可用）', style: _lbl),
            DropdownButtonFormField<String>(
              // 若目前選的攤位不在當天清單，value 設 null 避免 assert
              value: _stallOptions.any((st) => st.id == _stallId) ? _stallId : null,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              hint: const Text('選擇本攤位'),
              items: _stallOptions
                  .map((st) => DropdownMenuItem(value: st.id, child: Text('${st.label}  (${st.id})')))
                  .toList(),
              onChanged: (v) => setState(() => _stallId = v ?? _stallId),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('儲 存', style: TextStyle(letterSpacing: 4, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _lbl = TextStyle(letterSpacing: 2, color: Colors.white54, fontSize: 13);
