import 'package:flutter/material.dart';
import '../theme.dart';

/// 積分兌換檔位選擇。tier → points：100→100, 250→300, 400→500, 750→1000,
/// 1500→2000, 3000→4000。回傳選定 tier（取消回 null）。
Future<int?> showExchangePicker(BuildContext context) {
  const tiers = {100: 100, 250: 300, 400: 500, 750: 1000, 1500: 2000, 3000: 4000};
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
                  style: const TextStyle(fontSize: 18, color: AppColors.brown)),
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ],
      ),
    ),
  );
}
