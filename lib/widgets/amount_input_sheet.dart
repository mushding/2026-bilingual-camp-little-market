import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 通用金額/數量輸入 bottom sheet。回傳 int（取消回 null）。
Future<int?> showAmountInput(
  BuildContext context, {
  required String title,
  List<int> quickKeys = const [],
  String? hint,
  int? min,
  int? max,
  bool allowAll = false, // 「全部」鍵（提領用），回傳 -1
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _AmountSheet(
      title: title, quickKeys: quickKeys, hint: hint, min: min, max: max, allowAll: allowAll,
    ),
  );
}

class _AmountSheet extends StatefulWidget {
  final String title;
  final List<int> quickKeys;
  final String? hint;
  final int? min, max;
  final bool allowAll;
  const _AmountSheet(
      {required this.title, required this.quickKeys, this.hint, this.min, this.max, required this.allowAll});

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  final _c = TextEditingController();
  String? _err;

  void _submit() {
    final v = int.tryParse(_c.text.trim());
    if (v == null || v <= 0) {
      setState(() => _err = '請輸入正整數');
      return;
    }
    if (widget.min != null && v < widget.min!) {
      setState(() => _err = '不可小於 ${widget.min}');
      return;
    }
    if (widget.max != null && v > widget.max!) {
      setState(() => _err = '不可大於 ${widget.max}');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 28),
            decoration: InputDecoration(
              hintText: widget.hint,
              errorText: _err,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.quickKeys.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final k in widget.quickKeys)
                ActionChip(label: Text('$k'), onPressed: () => _c.text = '$k'),
            ]),
          ],
          const SizedBox(height: 16),
          Row(children: [
            if (widget.allowAll)
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, -1),
                  child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('全部')),
                ),
              ),
            if (widget.allowAll) const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _submit,
                child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('確定')),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
