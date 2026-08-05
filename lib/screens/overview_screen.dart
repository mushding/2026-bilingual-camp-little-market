import 'package:flutter/material.dart';
import '../data/camp_info.dart';
import '../services/l10n.dart';
import '../theme.dart';

/// 三天大架構 — 每天一張精簡時間軸。
class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: kCampDays.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.t('三天大架構', 'Daily Overview')),
          bottom: TabBar(
            indicatorColor: AppColors.yellow,
            labelColor: const Color(0xFFF2F7F2),
            unselectedLabelColor: const Color(0xFFB8CFC9),
            tabs: [
              for (final d in kCampDays)
                Tab(
                    text: '${d.label}\n${L10n.t(d.date, d.dateEn)}',
                    height: 56),
            ],
          ),
        ),
        body: TabBarView(
          children: [for (final d in kCampDays) _DayOverview(day: d)],
        ),
      ),
    );
  }
}

class _DayOverview extends StatelessWidget {
  final CampDay day;
  const _DayOverview({required this.day});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFFFFF8E1),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('👕 ${L10n.t(day.shirt, day.shirtEn)}',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 8),
        for (final (time, zh, en) in day.overview)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 56,
                  child: Text(time,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.tealDark)),
                ),
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 5, right: 12),
                  decoration: const BoxDecoration(
                    color: AppColors.sage,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(L10n.t(zh, en),
                      style: const TextStyle(fontSize: 15)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
