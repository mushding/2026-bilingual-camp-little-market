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
  late final TextEditingController _url;
  late final TextEditingController _staff;
  final _code = TextEditingController();
  late String _stallId;
  late bool _allTxn;
  bool _enrolling = false;

  @override
  void initState() {
    super.initState();
    final s = Settings.instance;
    _url = TextEditingController(text: s.backendUrl);
    _staff = TextEditingController(text: s.staffUid);
    _stallId = s.stallId;
    _allTxn = s.allTxnMode;
  }

  @override
  void dispose() {
    _url.dispose();
    _staff.dispose();
    _code.dispose();
    super.dispose();
  }

  void _snack(String m, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), backgroundColor: ok ? Colors.green : Colors.red));
  }

  Future<void> _enroll() async {
    // 註冊前先存 URL（enroll 要連對的 backend）
    await Settings.instance.setBackendUrl(_url.text);
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
    final s = Settings.instance;
    await s.setBackendUrl(_url.text);
    await s.setStaffUid(_staff.text);
    await s.setStallId(_stallId);
    await s.setAllTxnMode(_allTxn);
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
            const Text('Backend URL', style: _lbl),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'https://bilingual.smsk.church',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            const Text('正式：https://bilingual.smsk.church。模擬器：http://10.0.2.2:8000',
                style: TextStyle(fontSize: 12, color: Colors.white38)),
            const SizedBox(height: 20),

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

            const Text('本攤位', style: _lbl),
            DropdownButtonFormField<String>(
              value: _stallId,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: kStalls
                  .map((st) => DropdownMenuItem(value: st.id, child: Text('${st.label}  (${st.id})')))
                  .toList(),
              onChanged: (v) => setState(() => _stallId = v ?? _stallId),
            ),
            const SizedBox(height: 20),
            const Text('本機關主 UID（見證 / 公會防作弊用）', style: _lbl),
            TextField(
              controller: _staff,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: '同工卡 UID 或自訂字串',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('全交易測試模式'),
              subtitle: const Text('主畫面列出全部交易（測試/總控用）'),
              value: _allTxn,
              onChanged: (v) => setState(() => _allTxn = v),
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
