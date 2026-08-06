import 'package:flutter/material.dart';
import '../data/meal_menu.dart';
import '../theme.dart';

/// 餐費菜單 bottom sheet：看學生拿什麼就點什麼，自動加總。回傳總金額（取消回 null）。
/// [day] 預選天（通常從後端 current_day 帶入）；頂部仍可手動切換，
/// 後端連不上或天數不對時同工可自救。
Future<int?> showMealMenu(BuildContext context, {String day = 'D1'}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _MealMenuSheet(initialDay: kMealMenus.containsKey(day) ? day : 'D1'),
  );
}

class _MealMenuSheet extends StatefulWidget {
  final String initialDay;
  const _MealMenuSheet({required this.initialDay});

  @override
  State<_MealMenuSheet> createState() => _MealMenuSheetState();
}

class _MealMenuSheetState extends State<_MealMenuSheet> {
  late String _day = widget.initialDay;
  final Map<String, int> _counts = {}; // item name -> qty

  List<MealItem> get _menu => kMealMenus[_day]!;

  int get _total => _menu.fold(
      0, (sum, it) => sum + it.price * (_counts[it.name] ?? 0));

  void _switchDay(String d) => setState(() {
        _day = d;
        _counts.clear();
      });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('餐費菜單',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                for (final d in kMealMenus.keys)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(
                      label: Text(d),
                      selected: _day == d,
                      onSelected: (_) => _switchDay(d),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final it in _menu)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('${it.name}  \$${it.price}',
                                style: const TextStyle(fontSize: 15)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            visualDensity: VisualDensity.compact,
                            onPressed: (_counts[it.name] ?? 0) == 0
                                ? null
                                : () => setState(() =>
                                    _counts[it.name] = _counts[it.name]! - 1),
                          ),
                          SizedBox(
                            width: 24,
                            child: Text('${_counts[it.name] ?? 0}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline,
                                color: AppColors.tealDark),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() =>
                                _counts[it.name] = (_counts[it.name] ?? 0) + 1),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            Row(
              children: [
                Text('合計 \$$_total',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.tealDark)),
                const Spacer(),
                FilledButton(
                  onPressed: _total <= 0
                      ? null
                      : () => Navigator.pop(context, _total),
                  child: const Text('確認扣款'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
