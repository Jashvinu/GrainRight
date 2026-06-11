import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';

class FarmerAiGradingScreen extends StatelessWidget {
  const FarmerAiGradingScreen({super.key});

  static const _grade = 'A';
  static const _score = 86;

  Map<String, String> get _farmArgs {
    final args = Get.arguments;
    if (args is Map) {
      return {
        'farmName': '${args['farmName'] ?? 'Rajur Millet Plot'}',
        'crop': '${args['crop'] ?? 'Finger Millet'}',
        'village': '${args['village'] ?? 'Rajur'}',
      };
    }
    return const {
      'farmName': 'Rajur Millet Plot',
      'crop': 'Finger Millet',
      'village': 'Rajur',
    };
  }

  Future<void> _openHarvestSheet(BuildContext context) async {
    final bagSizeCtrl = TextEditingController(text: '50');
    final bagCountCtrl = TextEditingController(text: '12');

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final inset = MediaQuery.viewInsetsOf(context).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + inset),
          child: _HarvestBagSheet(
            bagSizeCtrl: bagSizeCtrl,
            bagCountCtrl: bagCountCtrl,
          ),
        );
      },
    );

    bagSizeCtrl.dispose();
    bagCountCtrl.dispose();

    if (result == null) return;
    final farm = _farmArgs;
    Get.toNamed(
      '/farmer/harvest-qr',
      arguments: {
        ...farm,
        ...result,
        'grade': _grade,
        'score': '$_score',
        'batchId': _batchId(),
      },
    );
  }

  String _batchId() {
    final now = DateTime.now();
    final date =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'KF-HV-$date-${now.millisecondsSinceEpoch % 10000}';
  }

  @override
  Widget build(BuildContext context) {
    final farm = _farmArgs;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('AI Grain Grading'),
        actions: [
          IconButton(
            tooltip: 'Help',
            onPressed: () => Get.snackbar(
              'AI Grading',
              'Use a clear grain photo on a plain background before generating the harvest QR.',
              snackPosition: SnackPosition.BOTTOM,
            ),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 104),
        children: [
          _GradingHero(
            farmName: farm['farmName']!,
            crop: farm['crop']!,
            village: farm['village']!,
            score: _score,
            grade: _grade,
          ),
          const SizedBox(height: 16),
          _PhotoCard(
            onTap: () {
              Get.snackbar(
                'Photo selected',
                'Sample grain photo loaded for grading preview.',
                snackPosition: SnackPosition.BOTTOM,
              );
            },
          ),
          const SizedBox(height: 16),
          const _QualityGrid(),
          const SizedBox(height: 16),
          const _RecommendationCard(),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _openHarvestSheet(context),
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('Generate Harvest QR'),
          ),
        ],
      ),
    );
  }
}

class _GradingHero extends StatelessWidget {
  final String farmName;
  final String crop;
  final String village;
  final String grade;
  final int score;

  const _GradingHero({
    required this.farmName,
    required this.crop,
    required this.village,
    required this.grade,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B5D2A), Color(0xFF4CAF50)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Harvest quality result',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$crop • $farmName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      village,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Container(
                width: 86,
                height: 86,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  grade,
                  style: const TextStyle(
                    color: AppTheme.green,
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: score / 100,
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$score / 100 quality score • Premium packaging eligible',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  final VoidCallback onTap;

  const _PhotoCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                height: 190,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.grain_rounded, color: Color(0xFFB8860B), size: 86),
                    Positioned(
                      left: 14,
                      top: 14,
                      child: _PhotoBadge(label: 'Plain background'),
                    ),
                    Positioned(
                      right: 14,
                      bottom: 14,
                      child: _PhotoBadge(label: 'Sample loaded'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Replace grain photo'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoBadge extends StatelessWidget {
  final String label;

  const _PhotoBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

class _QualityGrid extends StatelessWidget {
  const _QualityGrid();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Purity', '94%', Icons.verified_outlined, AppTheme.green),
      ('Moisture', '11%', Icons.water_drop_outlined, Color(0xFF1976D2)),
      ('Broken', '3%', Icons.scatter_plot_outlined, Color(0xFFE07800)),
      ('Foreign matter', '1%', Icons.filter_alt_outlined, AppTheme.green),
    ];

    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.85,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.$3, color: item.$4),
                const SizedBox(height: 8),
                Text(
                  item.$1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.$2,
                  style: TextStyle(
                    color: item.$4,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Row(
              children: [
                Icon(Icons.tips_and_updates_outlined, color: AppTheme.green),
                SizedBox(width: 10),
                Text(
                  'Next best action',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            SizedBox(height: 10),
            Text(
              'This batch is suitable for premium packaging. Keep moisture below 12%, print the harvest QR, and store bags away from direct floor contact.',
              style: TextStyle(
                color: AppTheme.textMuted,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HarvestBagSheet extends StatelessWidget {
  final TextEditingController bagSizeCtrl;
  final TextEditingController bagCountCtrl;

  const _HarvestBagSheet({
    required this.bagSizeCtrl,
    required this.bagCountCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Harvest Bag Details',
              style: TextStyle(
                color: AppTheme.greenDark,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Grade A from AI grading will be printed on the harvest QR sticker.',
              style: TextStyle(color: AppTheme.textMuted, height: 1.4),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: bagSizeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Bag size', suffixText: 'kg'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bagCountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Number of bags'),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () {
                final bagSize = double.tryParse(bagSizeCtrl.text.trim());
                final bagCount = int.tryParse(bagCountCtrl.text.trim());
                if (bagSize == null ||
                    bagSize <= 0 ||
                    bagCount == null ||
                    bagCount <= 0) {
                  Get.snackbar(
                    'Check bag details',
                    'Enter valid bag size and number of bags.',
                    snackPosition: SnackPosition.BOTTOM,
                  );
                  return;
                }
                Navigator.pop(context, {
                  'bagSizeKg': bagSize.toStringAsFixed(
                    bagSize.truncateToDouble() == bagSize ? 0 : 1,
                  ),
                  'bagCount': '$bagCount',
                  'totalKg': (bagSize * bagCount).toStringAsFixed(1),
                });
              },
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('Generate Harvest QR'),
            ),
          ],
        ),
      ),
    );
  }
}
