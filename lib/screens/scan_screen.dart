import 'dart:async';

import 'package:flutter/material.dart';
import '../theme.dart';
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
import 'bank_transfer_screen.dart';
import 'casino_table_screen.dart';
import 'guild_pending_screen.dart';
import 'mail_screen.dart';
import 'qr_scan_screen.dart';
import 'settings_screen.dart';
import 'topic1_screen.dart';

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
  String _bannerName = '';
  String _bannerGroup = '';
  Timer? _bannerTimer;
  Timer? _pollTimer;
  Timer? _tickTimer;
  DateTime? _tasksFetchedAt;
  bool _marketClosedShown = false;
  bool _closingSoonShown = false;

  @override
  void initState() {
    super.initState();
    // 每 8 秒輪詢市場狀態：市場關閉時跳通知請學員回禮堂
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _pollMarket());
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  /// 掃卡結果更新：記下拿到公會任務清單的時間點，讓待完成任務的倒數能
  /// 每秒即時遞減顯示（不必再掃一次卡才會更新）。
  void _setStudent(StudentState s) {
    _student = s;
    _tasksFetchedAt = DateTime.now();
    _tickTimer?.cancel();
    if (s.pendingTasks.isNotEmpty) {
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// 依 _tasksFetchedAt 至今經過的秒數，即時遞減 pendingTasks 的剩餘秒數。
  List<PendingTask> _liveTasks(StudentState s) {
    if (s.pendingTasks.isEmpty || _tasksFetchedAt == null) return s.pendingTasks;
    final elapsed = DateTime.now().difference(_tasksFetchedAt!).inSeconds;
    return s.pendingTasks
        .map((t) => PendingTask(t.gameKey, t.gameName, t.reward,
            (t.remainingSeconds - elapsed) < 0 ? 0 : t.remainingSeconds - elapsed))
        .toList();
  }

  Future<void> _pollMarket() async {
    try {
      final st = await ApiClient.appState();
      if (!mounted) return;
      if (st['market_open'] == true) {
        // 重新開市（當日截止後隔天）→ 重置提示閂，之後再截止能再次跳提醒
        _marketClosedShown = false;
        if (st['closing_soon'] == true && !_closingSoonShown) {
          _closingSoonShown = true;
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.yellow,
              title: const Text('⏰ 剩 5 分鐘'),
              content: const Text('本場小市集即將結束，請提醒學員把握時間、盡快完成交易。',
                  style: TextStyle(fontSize: 18, color: AppColors.brown)),
              actions: [
                FilledButton(
                    onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
              ],
            ),
          );
        }
        if (st['closing_soon'] != true) _closingSoonShown = false;
      } else if (!_marketClosedShown) {
        _marketClosedShown = true;
        _closingSoonShown = false;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.red,
            title: const Text('🔔 市場已關閉'),
            content: const Text('小市集結束，請學員停止交易，回到禮堂集合。',
                style: TextStyle(fontSize: 18)),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
            ],
          ),
        );
      }
    } catch (_) {/* 網路抖動忽略 */}
  }

  Stall get _stall => stallById(Settings.instance.stallId);
  // 交易類型一律只列本攤位允許的（不再有全交易測試模式 footgun）
  List<TxnType> get _allowed => _stall.txns;

  // 特殊攤位走專屬畫面（非標準掃卡流程）
  bool get _isCasino =>
      _stall.id == 'casino_21' || _stall.id == 'casino_dice';
  bool get _isGameStall => _stall.id.startsWith('game_');
  bool get _isMail => _stall.id == 'mail';
  bool get _isBank => _stall.id == 'bank';
  bool get _isTopic1 => _stall.id == 'topic1';

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
      await _lookup(uid);
    } catch (e) {
      _showBanner('$e', false);
      setState(() => _state = _S.idle);
    }
  }

  /// QR code 備援：手機無 NFC 時，掃卡片上的 QR 貼紙（內容＝UID）。
  Future<void> _scanQr() async {
    final uid = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (uid == null) return;
    setState(() {
      _state = _S.reading;
      _student = null;
      _txn = null;
      _banner = null;
    });
    try {
      await _lookup(uid);
    } catch (e) {
      _showBanner('$e', false);
      setState(() => _state = _S.idle);
    }
  }

  Future<void> _lookup(String uid) async {
    final s = await ApiClient.scan(uid: uid, stallId: _stall.id, action: 'lookup');
    setState(() {
      _setStudent(s);
      _txn = _allowed.firstWhere((t) => t != TxnType.lookup,
          orElse: () => TxnType.lookup);
      _state = _S.loaded;
    });
    if (!s.ok) _showBanner(s.message, false);
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
        final v = await _pickDollPrice();
        if (v == null) return;
        amount = v;
        break;
      case TxnType.grocery:
        final v = await showAmountInput(context,
            title: '${t.label} 售價', quickKeys: const [20, 50, 100, 200], hint: '輸入售價（真實物價）');
        if (v == null) return;
        amount = v;
        break;
      case TxnType.meal:
        // D1 下午攤位吃的／D2 午餐：攤主輸入該生消費總金額（金額不限檔）
        final v = await showAmountInput(context,
            title: '餐費金額', quickKeys: const [150], min: 1, hint: '輸入總金額（便當預設 150）');
        if (v == null) return;
        amount = v;
        break;
      case TxnType.day1RingToss:
        final n = await showAmountInput(context, title: '中圈數 (0–10)', max: 10, hint: '中幾圈');
        if (n == null) return;
        cost = 100;
        reward = (n < 0 ? 0 : n) * 100;
        break;
      case TxnType.day1Dart:
        final n = await showAmountInput(context, title: '命中數 (0–10)', max: 10, hint: '命中幾鏢');
        if (n == null) return;
        cost = 100;
        reward = (n < 0 ? 0 : n) * 20;
        break;
      case TxnType.day1Bingo:
        final win = await _bingoResult();
        if (win == null) return;
        cost = 100;
        reward = win ? 1000 : 0;
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
            title: '奉獻金額', quickKeys: const [100, 500, 1000], hint: '現金轉天國點數，同時 +0.5x 積分');
        if (v == null) return;
        amount = v;
        break;
      case TxnType.exchange:
        final v = await showExchangePicker(context);
        if (v == null) return;
        tier = v;
        break;
      case TxnType.witness:
        // 不需綁定關主：用本機自動裝置 id 防刷（每位同工各自一台）
        break;
      case TxnType.guildDraw:
        final v = await showAmountInput(context,
            title: '公會：抽幾個任務？', quickKeys: const [1, 2, 3, 4, 5], min: 1, max: 9,
            hint: '問學員要抽幾個');
        if (v == null) return;
        amount = v;
        break;
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
        staffUid: (t == TxnType.witness || t == TxnType.guildComplete)
            ? Settings.instance.deviceId
            : null,
      );
      setState(() {
        _setStudent(res);
        _state = _S.result;
      });
      _showResultBanner(res);
    } catch (e) {
      _showBanner('$e', false);
      setState(() => _state = _S.loaded);
    }
  }

  /// 交易結果 banner：帶姓名+組別，3 秒自動關（或按 X），關後回等待掃卡。
  /// 公會抽任務例外：結果停留在畫面上（列出抽到哪些關卡），關主按 X 才關，
  /// 方便讓學員仔細看抽到什麼。
  void _showResultBanner(StudentState res) {
    _bannerTimer?.cancel();
    setState(() {
      _banner = res.message;
      _bannerOk = res.ok;
      _bannerName = res.studentName;
      _bannerGroup = res.group;
    });
    if (res.action != 'guild_draw') {
      _bannerTimer = Timer(const Duration(seconds: 3), _dismissBanner);
    }
  }

  void _dismissBanner() {
    _bannerTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _banner = null;
      _bannerName = '';
      _bannerGroup = '';
      if (_state == _S.result) {
        _state = _S.idle;
        _student = null;
        _txn = null;
      }
    });
  }

  Future<bool?> _bingoResult() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('麻將賓果結果'),
          content: const Text('任一連線即中（賠 1000）'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('未中')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('中獎')),
          ],
        ),
      );

  /// 賣娃娃固定四檔：特大500／大300／中200／小100。
  Future<int?> _pickDollPrice() => showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('賣娃娃 — 選尺寸'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in const {'特大': 500, '大': 300, '中': 200, '小': 100}.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, e.value),
                    child: Text('${e.key} — \$${e.value}', style: const TextStyle(fontSize: 18)),
                  ),
                ),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ],
        ),
      );

  Future<bool> _confirm(StudentState s, TxnType t, int amount, int tier) async {
    String detail = t.label;
    if (amount > 0) detail += ' \$$amount';
    if (amount == -1) detail += ' 全部';
    if (tier > 0) detail += ' 兌換檔 \$$tier';
    if (t == TxnType.guildDraw) {
      detail += '\n\n⚠️ 請提醒學員：每個任務限時 15 分鐘，'
          '逾時未完成自動作廢並扣 \$100';
    }
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
          if (s.isAdmin)
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
          color: AppColors.yellow,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          const Icon(Icons.storefront, size: 18, color: AppColors.brown),
          const SizedBox(width: 8),
          Text('本攤位：${_stall.label}',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.brown)),
        ]),
      );

  Widget _bannerWidget() {
    final c = _bannerOk ? AppColors.teal : AppColors.red;
    final title = _bannerName.isEmpty
        ? null
        : '$_bannerName${_bannerGroup.isEmpty ? '' : '　[$_bannerGroup]'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.2),
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(_bannerOk ? Icons.check_circle : Icons.error, color: c),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null)
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(_banner!, style: const TextStyle(fontSize: 15)),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: _dismissBanner,
        ),
      ]),
    );
  }

  Widget _body() {
    // 特殊攤位：專屬入口
    if (_isCasino) return _entryButton('開賭桌', Icons.casino, () {
          Navigator.push(context, MaterialPageRoute(
              builder: (_) => CasinoTableScreen(table: _stall.id == 'casino_21' ? '21' : 'dice', stallId: _stall.id)));
        });
    if (_isMail) return _entryButton('郵政感謝卡登記', Icons.mail, () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const MailScreen()));
        });
    if (_isTopic1) return _entryButton('選小組整組加錢', Icons.groups, () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const Topic1Screen()));
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
                    Icon(Icons.contactless, size: 96, color: AppColors.sage),
                    SizedBox(height: 16),
                    Text('按「掃卡」並把卡片靠近手機背面', style: TextStyle(color: AppColors.muted)),
                  ]),
          ),
        ),
        if (_isBank && _state == _S.idle) ...[
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const BankTransferScreen())),
            icon: const Icon(Icons.swap_horiz),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('服務三：轉帳', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_isGameStall && _state == _S.idle) ...[
          FilledButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => GuildPendingScreen(stallId: _stall.id, stallLabel: _stall.label))),
            icon: const Icon(Icons.list_alt, size: 28),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('看待完成名單', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(height: 8),
        ],
        _scanButton(),
        const SizedBox(height: 8),
        _qrScanButton(),
      ]);
    }

    // loaded / submitting / result
    final s = _student!;
    // 小遊戲關：掃卡先驗有沒有抽到本關（沒抽到 → 明顯提示、不能結算）。
    // 流程：學員遊戲前掃一次確認有抽到 → 玩 → 玩完再掃一次按「完成關卡結算」。
    final thisTask = _isGameStall
        ? s.pendingTasks.where((pt) => pt.gameKey == _stall.id).firstOrNull
        : null;
    final gameBlocked = _isGameStall && _state == _S.loaded && thisTask == null;
    return Column(children: [
      StudentCard(s: s, liveTasks: _liveTasks(s)),
      const SizedBox(height: 16),
      if (gameBlocked)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.red.withValues(alpha: 0.15),
            border: Border.all(color: AppColors.red, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(children: [
            Icon(Icons.block, color: AppColors.red),
            SizedBox(width: 10),
            Expanded(
              child: Text('沒有抽到這關喔！\n請先到公會台抽任務再來闖關',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ]),
        )
      else if (_isGameStall && thisTask != null && _state == _S.loaded)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.mint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle, color: AppColors.tealDark),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '有抽到本關：${thisTask.gameName}（獎勵 \$${thisTask.reward}）\n'
                '剩 ${thisTask.remainingSeconds ~/ 60}:${(thisTask.remainingSeconds % 60).toString().padLeft(2, '0')}'
                '　遊戲完成後按下方結算',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ]),
        )
      else
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
            onPressed: _state == _S.submitting || gameBlocked ? null : _execute,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                  _state == _S.submitting
                      ? '處理中…'
                      : (_isGameStall ? '完成關卡結算' : '執 行'),
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

  /// 手機沒 NFC 感應：改掃卡片上的 QR 貼紙。
  Widget _qrScanButton() => OutlinedButton.icon(
        onPressed: _state == _S.reading ? null : _scanQr,
        icon: const Icon(Icons.qr_code_scanner, size: 24),
        label: const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('手機沒 NFC？掃 QR Code', style: TextStyle(fontSize: 15)),
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
