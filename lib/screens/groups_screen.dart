import 'package:flutter/material.dart';
import '../data/camp_info.dart';
import '../services/l10n.dart';
import '../theme.dart';

/// 小組名單與場地 — 10 組成員、輔導、教室對照。
class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t('小組名單與場地', 'Groups & Rooms'))),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: kGroups.length,
        itemBuilder: (context, i) => _GroupCard(group: kGroups[i]),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final CampGroup group;
  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final isEs = group.band == '國小';
    final venue = L10n.isEn
        ? (kVenueEn[group.churchVenue] ?? group.churchVenue)
        : group.churchVenue;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(L10n.t('第 ${group.number} 組', 'Group ${group.number}'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isEs ? AppColors.mint : AppColors.sky,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                      isEs
                          ? L10n.t('國小', 'Elementary')
                          : L10n.t('國中', 'Junior High'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.ink)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
                L10n.t('石小 ${group.classroom} ｜ 水庫 $venue',
                    'Shimen ES ${group.classroom} | Church: $venue'),
                style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                Text(L10n.t('輔導：', 'Coaches: '),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
                for (final c in group.coaches)
                  Text(
                      L10n.isEn
                          ? c.replaceAll('（美國同工）', ' (US team)')
                          : c,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.tealDark)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in group.students) _StudentChip(student: s),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentChip extends StatelessWidget {
  final CampStudent student;
  const _StudentChip({required this.student});

  @override
  Widget build(BuildContext context) {
    final grade =
        L10n.isEn ? (kGradeEn[student.grade] ?? student.grade) : student.grade;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border.all(color: AppColors.line, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            student.english.isEmpty
                ? student.name
                : '${student.name} ${student.english}',
            style: const TextStyle(fontSize: 14),
          ),
          Row(
            children: [
              Text(grade,
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.muted)),
              if (student.note != null) ...[
                const SizedBox(width: 4),
                Text('⚠ ${student.note}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.red,
                        fontWeight: FontWeight.bold)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
