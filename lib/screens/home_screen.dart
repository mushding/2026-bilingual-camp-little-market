import 'package:flutter/material.dart';
import '../services/l10n.dart';
import '../theme.dart';
import 'groups_screen.dart';
import 'maps_screen.dart';
import 'overview_screen.dart';
import 'rundown_screen.dart';
import 'scan_screen.dart';

/// 營會首頁 — 所有同工共用的入口。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Hero
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.tealDark,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L10n.t('2026 雙語營', '2026 Bilingual Camp'),
                      style: const TextStyle(
                          color: Color(0xFFF2F7F2),
                          fontSize: 26,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                      L10n.t('忠心好管家 ・ 08/07（五）– 08/09（日）',
                          'Faithful Steward ・ Aug 7 (Fri) – Aug 9 (Sun)'),
                      style: const TextStyle(
                          color: Color(0xFFCFE2CF), fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                      L10n.t('早上：石門國小 ／ 傍晚：水庫教會',
                          'AM: Shimen Elementary / PM: Shimen Reservoir Church'),
                      style: const TextStyle(
                          color: Color(0xFFCFE2CF), fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _MenuCard(
              icon: Icons.groups,
              color: AppColors.sage,
              title: L10n.t('小組名單與場地', 'Groups & Rooms'),
              subtitle: L10n.t('10 組成員、輔導、石小教室與水庫場地',
                  '10 groups: members, coaches, rooms at both sites'),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const GroupsScreen())),
            ),
            _MenuCard(
              icon: Icons.event_note,
              color: AppColors.yellow,
              title: L10n.t('三天細流', 'Detailed Rundown'),
              subtitle: L10n.t('各時段執行內容、各組備註',
                  'Slot-by-slot schedule for all 3 days'),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RundownScreen())),
            ),
            _MenuCard(
              icon: Icons.schedule,
              color: AppColors.sky,
              title: L10n.t('三天大架構', 'Daily Overview'),
              subtitle: L10n.t('一眼看懂每天時程', 'Each day at a glance'),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const OverviewScreen())),
            ),
            _MenuCard(
              icon: Icons.map,
              color: AppColors.mint,
              title: L10n.t('場地地圖', 'Maps'),
              subtitle: L10n.t('平面圖、小市集配置、動線（可縮放）',
                  'Floor plans, market layouts, routes (zoomable)'),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MapsScreen())),
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            _MenuCard(
              icon: Icons.nfc,
              color: AppColors.paper,
              title: L10n.t('小市集 ・ 攤主端', 'Market ・ Stall Mode'),
              subtitle: L10n.t('關主專用：NFC 感應卡片、交易',
                  'Stall keepers only: NFC card scan & transactions'),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ScanScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _MenuCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 28, color: AppColors.tealDark),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.muted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
