import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../config/brand_assets.dart';
import '../config/runtime_config.dart';
import '../config/theme.dart';
import '../utils/harvest_sticker_downloader.dart';

class HarvestQrScreen extends StatefulWidget {
  const HarvestQrScreen({super.key});

  @override
  State<HarvestQrScreen> createState() => _HarvestQrScreenState();
}

class _HarvestQrScreenState extends State<HarvestQrScreen> {
  final _stickerKey = GlobalKey();
  late final DateTime _generatedAt = DateTime.now().toUtc();
  bool _isDownloading = false;

  Map<String, String> get _args {
    final args = Get.arguments;
    if (args is Map) {
      return {
        'farmName': '${args['farmName'] ?? 'Rajur Millet Plot'}',
        'farmId': '${args['farmId'] ?? '--'}',
        'analysisId': '${args['analysisId'] ?? '--'}',
        'crop': '${args['crop'] ?? 'Finger Millet'}',
        'product': '${args['product'] ?? '--'}',
        'variety': '${args['variety'] ?? 'Unknown'}',
        'village': '${args['village'] ?? 'Rajur'}',
        'farmerName': '${args['farmerName'] ?? 'Farmer'}',
        'farmerId': '${args['farmerId'] ?? '--'}',
        'grade': '${args['grade'] ?? 'A'}',
        'score': '${args['score'] ?? '86'}',
        'standards': '${args['standards'] ?? 'Pending'}',
        'bagSizeKg': '${args['bagSizeKg'] ?? '50'}',
        'bagCount': '${args['bagCount'] ?? '12'}',
        'totalKg': '${args['totalKg'] ?? '600.0'}',
        'moisture': '${args['moisture'] ?? '--'}',
        'moistureSource': '${args['moistureSource'] ?? '--'}',
        'farmLatitude': '${args['farmLatitude'] ?? '--'}',
        'farmLongitude': '${args['farmLongitude'] ?? '--'}',
        'grader': '${args['grader'] ?? 'Microservice'}',
        'batchId': '${args['batchId'] ?? 'KF-HV-20260606-001'}',
        'reviewStatus': '${args['reviewStatus'] ?? 'not_required'}',
        'actorRole': '${args['actorRole'] ?? 'farmer'}',
        'fpcCustomerId': '${args['fpcCustomerId'] ?? ''}',
        'fpcCustomerName': '${args['fpcCustomerName'] ?? ''}',
      };
    }
    return const {
      'farmName': 'Rajur Millet Plot',
      'farmId': '--',
      'analysisId': '--',
      'crop': 'Finger Millet',
      'product': '--',
      'variety': 'Finger Millet',
      'village': 'Rajur',
      'farmerName': 'Farmer',
      'farmerId': '--',
      'grade': 'A',
      'score': '86',
      'standards': 'Pending',
      'bagSizeKg': '50',
      'bagCount': '12',
      'totalKg': '600.0',
      'moisture': '--',
      'moistureSource': '--',
      'farmLatitude': '--',
      'farmLongitude': '--',
      'grader': 'Microservice',
      'batchId': 'KF-HV-20260606-001',
      'reviewStatus': 'missing',
      'actorRole': 'farmer',
      'fpcCustomerId': '',
      'fpcCustomerName': '',
    };
  }

  List<String> get _missingReasons {
    final a = _args;
    final missing = <String>[];
    bool empty(String key) {
      final value = (a[key] ?? '').trim();
      return value.isEmpty || value == '--' || value.toLowerCase() == 'unknown';
    }

    if (empty('analysisId')) missing.add('Complete grain grading');
    if (empty('farmerId')) missing.add('Complete farmer profile');
    if (empty('farmId')) missing.add('Select a saved farm');
    if (empty('batchId')) missing.add('Add batch ID');
    if (empty('bagSizeKg') || empty('bagCount') || empty('totalKg')) {
      missing.add('Add bag details');
    }
    if (empty('moisture')) missing.add('Confirm moisture');
    if (empty('grade')) missing.add('Complete grade result');
    final review = (a['reviewStatus'] ?? '').trim();
    if (review == 'pending' || review == 'missing') {
      missing.add('Wait for FPO review approval');
    }
    return missing;
  }

  bool get _canGenerate => _missingReasons.isEmpty;

  Map<String, dynamic> get _publicTracePayload {
    final a = _args;
    return {
      'brand': 'Kalsubai Farms',
      'traceType': 'harvest',
      'traceVersion': 2,
      'generatedAt': _generatedAt.toIso8601String(),
      'analysisId': a['analysisId'],
      'batchId': a['batchId'],
      'farm': a['farmName'],
      'farmId': a['farmId'],
      'product': a['product'],
      'farmerId': a['farmerId'],
      'village': a['village'],
      'farmerName': a['farmerName'],
      'crop': a['crop'],
      'variety': a['variety'],
      'standards': a['standards'],
      'grade': a['grade'],
      'score': a['score'],
      'bagSizeKg': a['bagSizeKg'],
      'bagCount': a['bagCount'],
      'totalKg': a['totalKg'],
      'moisture': a['moisture'],
      'moistureSource': a['moistureSource'],
      'farmLatitude': a['farmLatitude'],
      'farmLongitude': a['farmLongitude'],
      'grader': a['grader'],
      'reviewStatus': a['reviewStatus'],
      'actorRole': a['actorRole'],
      if ((a['fpcCustomerId'] ?? '').isNotEmpty)
        'fpcCustomerId': a['fpcCustomerId'],
      if ((a['fpcCustomerName'] ?? '').isNotEmpty)
        'fpcCustomerName': a['fpcCustomerName'],
      'verifiedAt': _generatedAt.toIso8601String(),
    };
  }

  String get _qrData {
    final encoded = base64Url
        .encode(utf8.encode(jsonEncode(_publicTracePayload)))
        .replaceAll('=', '');
    return RuntimeConfig.publicTraceUrl(encoded);
  }

  Future<void> _downloadSticker() async {
    if (!_canGenerate) {
      Get.snackbar(
        'QR locked',
        _missingReasons.join(', '),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final boundary =
        _stickerKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    setState(() => _isDownloading = true);
    try {
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data?.buffer.asUint8List();
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Sticker image was empty.');
      }
      final fileName = 'kalsubai-harvest-${_args['batchId']}.png';
      final savedTo = await saveHarvestStickerBytes(
        Uint8List.fromList(bytes),
        fileName,
      );
      if (!mounted) return;
      Get.snackbar(
        'Harvest sticker ready',
        'Saved $savedTo',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (_) {
      if (!mounted) return;
      Get.snackbar(
        'Download failed',
        'Could not export the sticker image.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _args;
    final missingReasons = _missingReasons;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Harvest QR')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          if (missingReasons.isNotEmpty) ...[
            _QrLockCard(reasons: missingReasons),
            const SizedBox(height: 12),
          ],
          RepaintBoundary(
            key: _stickerKey,
            child: _HarvestStickerCard(args: a, qrData: _qrData),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Sticker Use',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Download this card and print it as a bag sticker. The QR opens a public harvest trace card with batch, farm, grade and bag details.',
                  style: TextStyle(color: AppTheme.textMuted, height: 1.45),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isDownloading || !_canGenerate ? null : _downloadSticker,
                  icon: _isDownloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(
                    _isDownloading ? 'Preparing' : 'Download sticker',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QrLockCard extends StatelessWidget {
  final List<String> reasons;

  const _QrLockCard({required this.reasons});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4DB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.gold),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded, color: AppTheme.earth),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'QR locked',
                  style: TextStyle(
                    color: AppTheme.earth,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  reasons.join(' • '),
                  style: const TextStyle(
                    color: AppTheme.earth,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HarvestStickerCard extends StatelessWidget {
  final Map<String, String> args;
  final String qrData;

  const _HarvestStickerCard({required this.args, required this.qrData});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Image.asset(BrandAssets.logo, width: 48, height: 48),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kalsubai Farms',
                      style: TextStyle(
                        color: AppTheme.greenDark,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Harvest Trace Sticker',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final sideBySide = constraints.maxWidth >= 290;
              final qrSize = sideBySide
                  ? (constraints.maxWidth * 0.48).clamp(152.0, 192.0).toDouble()
                  : (constraints.maxWidth - 64).clamp(216.0, 268.0).toDouble();
              final qrBox = _StickerQrBox(qrData: qrData, size: qrSize);
              final summary = _HarvestSummaryPanel(args: args);
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: sideBySide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          qrBox,
                          const SizedBox(width: 12),
                          Expanded(child: summary),
                        ],
                      )
                    : Column(
                        children: [
                          qrBox,
                          const SizedBox(height: 12),
                          summary,
                        ],
                      ),
              );
            },
          ),
          const SizedBox(height: 14),
          _StickerDetailGrid(
            details: [
              _StickerDetail(label: 'Batch', value: args['batchId']!),
              _StickerDetail(label: 'Analysis ID', value: args['analysisId']!),
              _StickerDetail(label: 'Crop', value: args['crop']!),
              _StickerDetail(label: 'Product', value: args['product']!),
              _StickerDetail(label: 'Variety', value: args['variety']!),
              _StickerDetail(label: 'Farm', value: args['farmName']!),
              _StickerDetail(label: 'Farm ID', value: args['farmId']!),
              _StickerDetail(label: 'Village', value: args['village']!),
              _StickerDetail(label: 'Farmer', value: args['farmerName']!),
              _StickerDetail(label: 'Farmer ID', value: args['farmerId']!),
              _StickerDetail(
                label: 'Moisture',
                value: _withPercent(args['moisture']!),
              ),
              _StickerDetail(
                label: 'Location',
                value: '${args['farmLatitude']}, ${args['farmLongitude']}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StickerMetric(
                label: 'Bag Size',
                value: '${args['bagSizeKg']} kg',
              ),
              _StickerMetric(label: 'Bags', value: args['bagCount']!),
              _StickerMetric(label: 'Total', value: '${args['totalKg']} kg'),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.greenPale.withValues(alpha: 0.74),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'AI Grade ${args['grade']} • Score ${args['score']}/100 • ${args['standards']} • ${args['grader']}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StickerQrBox extends StatelessWidget {
  final String qrData;
  final double size;

  const _StickerQrBox({required this.qrData, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
            data: qrData,
            version: QrVersions.auto,
            size: size,
            gapless: true,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scan harvest QR',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.greenDark,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _HarvestSummaryPanel extends StatelessWidget {
  final Map<String, String> args;

  const _HarvestSummaryPanel({required this.args});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 210),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.greenPale.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Grade',
            style: TextStyle(
              color: AppTheme.greenDark,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              args['grade']!,
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 54,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _StickerSummaryLine(
            label: 'Location',
            value: _harvestLocation(args),
          ),
          _StickerSummaryLine(
            label: 'Harvest Yield',
            value: _yieldLabel(args),
          ),
          _StickerSummaryLine(
            label: 'Rating',
            value: _ratingLabel(args),
          ),
        ],
      ),
    );
  }
}

class _StickerSummaryLine extends StatelessWidget {
  final String label;
  final String value;

  const _StickerSummaryLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              height: 1.16,
            ),
          ),
        ],
      ),
    );
  }
}

String _harvestLocation(Map<String, String> args) {
  final village = (args['village'] ?? '').trim();
  if (village.isNotEmpty && village != '--') return village;
  final lat = (args['farmLatitude'] ?? '').trim();
  final lng = (args['farmLongitude'] ?? '').trim();
  if (lat.isEmpty || lng.isEmpty || lat == '--' || lng == '--') return '--';
  return '$lat, $lng';
}

String _yieldLabel(Map<String, String> args) {
  final total = (args['totalKg'] ?? '').trim();
  final bags = (args['bagCount'] ?? '').trim();
  if (total.isEmpty || total == '--') return '--';
  final totalLabel = total.toLowerCase().contains('kg') ? total : '$total kg';
  if (bags.isEmpty || bags == '--') return totalLabel;
  return '$totalLabel / $bags bags';
}

String _ratingLabel(Map<String, String> args) {
  final score = (args['score'] ?? '').trim();
  if (score.isEmpty || score == '--') return '--';
  return score.contains('/') ? score : '$score/100';
}

class _StickerDetail {
  final String label;
  final String value;

  const _StickerDetail({required this.label, required this.value});
}

class _StickerDetailGrid extends StatelessWidget {
  final List<_StickerDetail> details;

  const _StickerDetailGrid({required this.details});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 320;
        final width = useTwoColumns
            ? (constraints.maxWidth - 10) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: details
              .map(
                (detail) => SizedBox(
                  width: width,
                  child: _StickerDetailTile(
                    label: detail.label,
                    value: detail.value,
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _StickerDetailTile extends StatelessWidget {
  final String label;
  final String value;

  const _StickerDetailTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StickerMetric extends StatelessWidget {
  final String label;
  final String value;

  const _StickerMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _withPercent(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == '--') return trimmed.isEmpty ? '--' : trimmed;
  return trimmed.endsWith('%') ? trimmed : '$trimmed%';
}
