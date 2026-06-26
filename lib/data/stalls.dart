import '../models/txn_type.dart';

/// 攤位設定 — 對應 docs/app/30 §1、docs/10~12 各日攤位。
/// stall_id → 顯示名 + 允許的交易集合（lookup 一律隱含可用）+ 出現在哪幾天。
class Stall {
  final String id;
  final String label;
  final List<TxnType> txns;
  final Set<String> days;  // 'D1'/'D2'/'D3'
  const Stall(this.id, this.label, this.txns, this.days);
}

const _d1 = {'D1'};
const _d23 = {'D2', 'D3'};
const _all = {'D1', 'D2', 'D3'};

/// 9 款小遊戲關（皆走 guildComplete，差別在 stall_id）。
const _games = {
  'game_color': '顏色分類',
  'game_password': '終極密碼',
  'game_moving': '搬家人工',
  'game_basketball': '投籃高手',
  'game_plane': '丟紙飛機',
  'game_balloon': '拍氣球',
  'game_charades': '比手畫腳',
  'game_memory': '記憶翻牌',
  'game_tangram': '七巧板',
};

final List<Stall> kStalls = [
  // Day1 技能攤（只有 D1）
  const Stall('day1_doll', '賣娃娃', [TxnType.day1SellDoll], _d1),
  const Stall('day1_ring', '套圈圈', [TxnType.day1RingToss], _d1),
  const Stall('day1_dart', '射飛鏢', [TxnType.day1Dart], _d1),
  const Stall('day1_bingo', '麻將賓果', [TxnType.day1Bingo], _d1),
  // 全程
  const Stall('bank', '銀行', [TxnType.bankDeposit, TxnType.bankWithdraw], _all),
  const Stall('meal', '餐費', [TxnType.meal], _all),
  // Day2/3 服務攤
  const Stall('witness', '聊天聽見證', [TxnType.witness], _d23),
  const Stall('donation', '舊鞋救命', [TxnType.donation], _d23),
  const Stall('exchange', '積分兌換', [TxnType.exchange], _d23),
  const Stall('grocery', '雜貨店', [TxnType.grocery], _d23),
  const Stall('mail', '郵政', [TxnType.mailKp], _d23),
  const Stall('casino_21', '賭場21點', [TxnType.casino21], _d23),
  const Stall('casino_dice', '賭場大小骰子', [TxnType.casinoDice], _d23),
  const Stall('guild', '公會台', [TxnType.guildDraw], _d23),
  // 9 款小遊戲關（Day2/3）
  for (final e in _games.entries) Stall(e.key, e.value, const [TxnType.guildComplete], _d23),
];

Stall stallById(String id) =>
    kStalls.firstWhere((s) => s.id == id, orElse: () => kStalls.first);

/// 某一天可用的攤位（給設定畫面下拉同步）。
List<Stall> stallsForDay(String day) =>
    kStalls.where((s) => s.days.contains(day)).toList();
