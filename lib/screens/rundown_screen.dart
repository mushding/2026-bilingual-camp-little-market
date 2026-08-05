import 'package:flutter/material.dart';
import '../data/camp_info.dart';
import '../services/l10n.dart';
import '../theme.dart';
import 'maps_screen.dart';

/// 三天細流 — Day1/2/3 分頁，每時段一張卡。
class RundownScreen extends StatelessWidget {
  const RundownScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: kCampDays.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.t('三天細流', 'Detailed Rundown')),
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
          children: [for (final d in kCampDays) _DayRundown(day: d)],
        ),
      ),
    );
  }
}

class _DayRundown extends StatelessWidget {
  final CampDay day;
  const _DayRundown({required this.day});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: const Color(0xFFFFF8E1),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('👕 ${L10n.t(day.shirt, day.shirtEn)}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(L10n.t(day.summary, day.summaryEn),
                    style:
                        const TextStyle(fontSize: 13, color: AppColors.muted)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        for (final item in day.rundown) _RundownCard(item: item),
        if (day.maps.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text(
                L10n.t('${day.label} 地圖', '${day.label} Maps'),
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.tealDark)),
          ),
          for (final (asset, capZh, capEn) in day.maps)
            MapImageCard(asset: asset, caption: L10n.t(capZh, capEn)),
        ],
      ],
    );
  }
}

class _RundownCard extends StatelessWidget {
  final RundownItem item;
  const _RundownCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final title =
        L10n.isEn && item.titleEn != null ? item.titleEn! : item.title;
    final place =
        L10n.isEn && item.placeEn != null ? item.placeEn! : item.place;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.tealDark,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item.duration == null
                        ? item.time
                        : '${item.time} (${item.duration})',
                    style: const TextStyle(
                        color: Color(0xFFF2F7F2),
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(title,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            if (L10n.isEn && item.titleEn != null)
              Text(item.title,
                  style:
                      const TextStyle(fontSize: 13, color: AppColors.muted)),
            Text('📍 $place',
                style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            if (item.details.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final line in item.details) _DetailLine(text: line),
            ],
            if (item.sideNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.mint.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(L10n.t('各組備註', 'Team notes'),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.teal)),
                    const SizedBox(height: 4),
                    for (final line in item.sideNotes) _DetailLine(text: line),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一行執行內容：把開頭的【組別】渲染成彩色標籤。
class _DetailLine extends StatelessWidget {
  final String text;
  const _DetailLine({required this.text});

  static const _tagColors = {
    '主持': Color(0xFFB02A5B),
    '輔導': Color(0xFF1D5CB0),
    '生活': Color(0xFF217A43),
    '多媒': Color(0xFF7B3FB5),
    '活動': Color(0xFFA2611A),
    '企劃': Color(0xFFA2611A),
    '關主': Color(0xFFA2611A),
  };

  Color _colorFor(String tag) {
    for (final e in _tagColors.entries) {
      if (tag.contains(e.key)) return e.value;
    }
    return const Color(0xFF3F4A5C);
  }

  @override
  Widget build(BuildContext context) {
    final match = RegExp(r'^【(.+?)】(.*)$').firstMatch(text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: match == null
          ? Text('・$text', style: const TextStyle(fontSize: 14))
          : Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: '【${match.group(1)}】',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _colorFor(match.group(1)!),
                  ),
                ),
                TextSpan(
                    text: match.group(2),
                    style: const TextStyle(fontSize: 14)),
              ]),
            ),
    );
  }
}
