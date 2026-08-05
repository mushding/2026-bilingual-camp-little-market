import 'package:flutter/material.dart';
import '../services/l10n.dart';
import '../theme.dart';

/// 場地地圖專區 — 平面圖、小市集配置、動線。點圖可全螢幕縮放。
class MapsScreen extends StatelessWidget {
  const MapsScreen({super.key});

  // (section zh, section en, [(asset, caption zh, caption en)])
  static const _sections = <(String, String, List<(String, String, String)>)>[
    ('平面圖', 'Floor Plans', [
      ('assets/maps/shimen_floorplan.jpg', '石門國小平面圖（早上主場地）',
          'Shimen Elementary floor plan (AM site)'),
      ('assets/maps/church_floorplan.jpg', '水庫教會平面圖（傍晚以後場地）',
          'Shimen Reservoir Church floor plan (PM site)'),
    ]),
    ('Day 1 小市集（水庫教會）', 'Day 1 Market (Church)', [
      ('assets/maps/market1.jpg', '小市集一・晴天', 'Market 1 — fair weather'),
      ('assets/maps/market1_rain.jpg', '小市集一・雨備', 'Market 1 — rain backup'),
    ]),
    ('Day 2/3 小市集（石門國小）', 'Day 2/3 Market (Shimen ES)', [
      ('assets/maps/market23.jpg', '小市集二／三', 'Market 2/3'),
      ('assets/maps/market23_rain.jpg', '小市集二／三・雨備',
          'Market 2/3 — rain backup'),
    ]),
    ('動線與場地', 'Routes & Venues', [
      ('assets/maps/day2_lunch_route.jpg', '第二天午餐動線（石小川堂）',
          'Day 2 lunch route (Shimen ES hallway)'),
      ('assets/maps/day2_interest_venue.jpg', '第二天興趣分組場地（石門國小）',
          'Day 2 interest group venues (Shimen ES)'),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t('場地地圖', 'Maps'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final (zh, en, images) in _sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Text(L10n.t(zh, en),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.tealDark)),
            ),
            for (final (asset, capZh, capEn) in images)
              MapImageCard(asset: asset, caption: L10n.t(capZh, capEn)),
          ],
        ],
      ),
    );
  }
}

/// 地圖卡片（點擊全螢幕縮放）— 地圖頁與細流頁共用。
class MapImageCard extends StatelessWidget {
  final String asset;
  final String caption;
  const MapImageCard({super.key, required this.asset, required this.caption});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => _FullscreenImage(asset: asset, caption: caption)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Image.asset(asset, fit: BoxFit.cover),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(caption,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  const Icon(Icons.zoom_in, size: 18, color: AppColors.muted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullscreenImage extends StatelessWidget {
  final String asset;
  final String caption;
  const _FullscreenImage({required this.asset, required this.caption});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(caption, style: const TextStyle(fontSize: 15)),
      ),
      body: InteractiveViewer(
        maxScale: 6,
        child: Center(child: Image.asset(asset)),
      ),
    );
  }
}
