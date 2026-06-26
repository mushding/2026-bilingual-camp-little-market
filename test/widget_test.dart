import 'package:flutter_test/flutter_test.dart';

import 'package:flyyoung_app/data/stalls.dart';
import 'package:flyyoung_app/models/txn_type.dart';

void main() {
  test('每個攤位至少有一個非 lookup 交易', () {
    for (final s in kStalls) {
      expect(s.txns.isNotEmpty, true, reason: '${s.id} 無交易');
    }
  });

  test('stallById 回退不丟例外', () {
    expect(stallById('nope').id, kStalls.first.id);
    expect(stallById('bank').label, '銀行');
  });

  test('TxnType action 字串完整', () {
    expect(TxnType.donation.action, 'donate');
    expect(TxnType.exchange.action, 'exchange_points');
  });
}
