import 'package:flutter/material.dart';
import '../models/student_state.dart';

/// 顯示學生：中文名 / 現金 / 積分 / 天國點數 / 定存本利。
class StudentCard extends StatelessWidget {
  final StudentState s;
  const StudentCard({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.studentName.isEmpty ? '（未綁定）' : s.studentName,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(s.uid, style: const TextStyle(fontFamily: 'monospace', color: Colors.white38, fontSize: 12)),
            const Divider(height: 20),
            Wrap(spacing: 18, runSpacing: 8, children: [
              _stat('現金', '\$${s.balance}', Colors.greenAccent),
              _stat('積分', '${s.points}', Colors.amberAccent),
              _stat('天國點數', '${s.kingdomPoints}', const Color(0xFFc9a0ff)),
              _stat('定存本利', '\$${s.depositBalance}', Colors.lightBlueAccent),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c)),
        ],
      );
}
