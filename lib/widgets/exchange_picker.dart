import 'package:flutter/material.dart';

/// 積分兌換檔位選擇。tier → points：500→500, 1000→1000, 2500→3000, 4000→5000, 7500→10000。
/// 回傳選定 tier（取消回 null）。
Future<int?> showExchangePicker(BuildContext context) {
  const tiers = {500: 500, 1000: 1000, 2500: 3000, 4000: 5000, 7500: 10000};
  return showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('選擇兌換檔位', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          for (final e in tiers.entries)
            ListTile(
              title: Text('花 \$${e.key}'),
              trailing: Text('+${e.value} 積分',
                  style: const TextStyle(fontSize: 18, color: Colors.amberAccent)),
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ],
      ),
    ),
  );
}
