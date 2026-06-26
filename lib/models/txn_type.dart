/// 交易類型 — 對應 docs/app/30 §2。
/// 每個 TxnType 帶：顯示名、後端 action、是否需 input。
enum TxnType {
  lookup('查詢', 'lookup'),
  day1SellDoll('賣娃娃', 'debit'),
  day1RingToss('套圈圈', 'game_settle'),
  day1Dart('射飛鏢', 'game_settle'),
  day1Bingo('麻將賓果', 'game_settle'),
  bankDeposit('定存', 'deposit'),
  bankWithdraw('提領本利', 'withdraw'),
  witness('分享見證', 'credit_kp'),
  donation('舊鞋救命（奉獻）', 'donate'),
  exchange('積分兌換', 'exchange_points'),
  grocery('雜貨店', 'debit'),
  mailKp('郵政感謝卡', 'mail_kp'),
  meal('餐費', 'meal'),
  casino21('賭場21點', 'casino'),
  casinoDice('賭場大小骰子', 'casino'),
  guildDraw('公會抽', 'guild_draw'),
  guildComplete('小遊戲完成', 'guild_complete');

  final String label;
  final String action;
  const TxnType(this.label, this.action);
}
