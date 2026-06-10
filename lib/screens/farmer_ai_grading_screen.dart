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
              'Use a clear millet grain photo on a plain background.',
              snackPosition: SnackPosition.BOTTOM,
            ),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openHarvestSheet(context),
        icon: const Icon(Icons.qr_code_2_rounded),
        label: const Text('Harvest QR'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
        children: [
          _InfoBanner(farmName: farm['farmName']!, crop: farm['crop']!),
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
          const _GradeResultCard(grade: _grade, score: _score),
          const SizedBox(height: 16),
          const _QualityGrid(),
          const SizedBox(height: 16),
          const _RecommendationCard(),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String farmName;
  final String crop;

  const _InfoBanner({required this.farmName, required this.crop});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.greenPale.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: AppTheme.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$crop quality grading for $farmName',
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            children: [
              Container(
                height: 190,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.grain_rounded,
                      color: Color(0xFFB8860B),
                      size: 86,
                    ),
                    Positioned(
                      right: 14,
                      bottom: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Sample loaded',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
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

class _GradeResultCard extends StatelessWidget {
  final String grade;
  final int score;

  const _GradeResultCard({required this.grade, required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: AppTheme.greenPale,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.green.withValues(alpha: 0.2)),
            ),
            alignment: Alignment.center,
            child: Text(
              grade,
              style: const TextStyle(
                color: AppTheme.green,
                fontSize: 46,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Grade Generated',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$score / 100 quality score',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: score / 100,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                  color: AppTheme.green,
                  backgroundColor: AppTheme.greenPale,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QualityGrid extends StatelessWidget {
  const _QualityGrid();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Purity', '94%', AppTheme.green),
      ('Moisture', '11%', Color(0xFF1976D2)),
      ('Broken', '3%', Color(0xFFE07800)),
      ('Foreign Matter', '1%', AppTheme.green),
    ];

    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.35,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
              const SizedBox(height: 5),
              Text(
                item.$2,
                style: TextStyle(
                  color: item.$3,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.tips_and_updates_outlined, color: AppTheme.green),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'This batch is suitable for premium packaging. Keep moisture below 12% before sealing the harvest sticker.',
              style: TextStyle(
                color: AppTheme.textMuted,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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
      borderRadius: BorderRadius.circular(22),
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
              decoration: const InputDecoration(
                labelText: 'Bag size',
                suffixText: 'kg',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bagCountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Number of bags'),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
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
