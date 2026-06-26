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
            Row(children: [
              Flexible(
                child: Text(s.studentName.isEmpty ? '（未綁定）' : s.studentName,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              ),
              if (s.group.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade700,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(s.group, style: const TextStyle(fontSize: 14)),
                ),
              ],
            ]),
            const SizedBox(height: 4),
            Text(s.uid, style: const TextStyle(fontFamily: 'monospace', color: Colors.white38, fontSize: 12)),
            const Divider(height: 20),
            Wrap(spacing: 18, runSpacing: 8, children: [
              _stat('現金', '\$${s.balance}', Colors.greenAccent),
              _stat('積分', '${s.points}', Colors.amberAccent),
              _stat('天國點數', '${s.kingdomPoints}', const Color(0xFFc9a0ff)),
              _stat('定存本利', '\$${s.depositBalance}', Colors.lightBlueAccent),
            ]),
            if (s.pendingTasks.isNotEmpty) ...[
              const Divider(height: 20),
              const Text('公會待完成任務', style: TextStyle(fontSize: 11, color: Colors.white54)),
              const SizedBox(height: 4),
              ...s.pendingTasks.map(_taskRow),
            ],
          ],
        ),
      ),
    );
  }

  Widget _taskRow(PendingTask t) {
    final mm = t.remainingSeconds ~/ 60, ss = t.remainingSeconds % 60;
    final urgent = t.remainingSeconds <= 120;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        const Icon(Icons.assignment, size: 16, color: Colors.orangeAccent),
        const SizedBox(width: 6),
        Expanded(child: Text('${t.gameName}（獎勵 ${t.reward}）')),
        Text('剩 ${mm}:${ss.toString().padLeft(2, '0')}',
            style: TextStyle(
                color: urgent ? Colors.redAccent : Colors.white70,
                fontWeight: urgent ? FontWeight.bold : FontWeight.normal)),
      ]),
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
