import 'package:flutter/material.dart';
import '../data/stalls.dart';
import '../services/settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  late final TextEditingController _staff;
  late String _stallId;
  late bool _admin;
  late bool _allTxn;

  @override
  void initState() {
    super.initState();
    final s = Settings.instance;
    _url = TextEditingController(text: s.backendUrl);
    _staff = TextEditingController(text: s.staffUid);
    _stallId = s.stallId;
    _admin = s.adminMode;
    _allTxn = s.allTxnMode;
  }

  @override
  void dispose() {
    _url.dispose();
    _staff.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = Settings.instance;
    await s.setBackendUrl(_url.text);
    await s.setStaffUid(_staff.text);
    await s.setStallId(_stallId);
    await s.setAdminMode(_admin);
    await s.setAllTxnMode(_allTxn);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
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
                hintText: 'http://192.168.1.10:8000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            const Text('Android 模擬器用 10.0.2.2；實機填電腦/伺服器 IP 或 Cloud Run 網址',
                style: TextStyle(fontSize: 12, color: Colors.white38)),
            const SizedBox(height: 20),
            const Text('本攤位', style: _lbl),
            DropdownButtonFormField<String>(
              value: _stallId,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: kStalls
                  .map((s) => DropdownMenuItem(
                      value: s.id, child: Text('${s.label}  (${s.id})')))
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
              title: const Text('總控模式（顯示管理畫面）'),
              value: _admin,
              onChanged: (v) => setState(() => _admin = v),
            ),
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
