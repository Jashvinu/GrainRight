import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../config/brand_assets.dart';
import '../config/theme.dart';
import '../utils/harvest_sticker_downloader.dart';

class HarvestQrScreen extends StatefulWidget {
  const HarvestQrScreen({super.key});

  @override
  State<HarvestQrScreen> createState() => _HarvestQrScreenState();
}

class _HarvestQrScreenState extends State<HarvestQrScreen> {
  final _stickerKey = GlobalKey();
  bool _isDownloading = false;

  Map<String, String> get _args {
    final args = Get.arguments;
    if (args is Map) {
      return {
        'farmName': '${args['farmName'] ?? 'Rajur Millet Plot'}',
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
      };
    }
      return const {
        'farmName': 'Rajur Millet Plot',
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
    };
  }

  String get _qrData {
    final a = _args;
    return jsonEncode({
      'brand': 'Kalsubai Farms',
      'batchId': a['batchId'],
      'farm': a['farmName'],
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
      'verifiedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _downloadSticker() async {
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
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Harvest QR')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
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
                  'Download this card and print it as a bag sticker. The QR contains batch, farm, grade and bag details.',
                  style: TextStyle(color: AppTheme.textMuted, height: 1.45),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isDownloading ? null : _downloadSticker,
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
              _GradeSeal(grade: args['grade']!),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.white,
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 142,
                    gapless: true,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StickerLine(label: 'Batch', value: args['batchId']!),
                      _StickerLine(label: 'Crop', value: args['crop']!),
                      _StickerLine(label: 'Product', value: args['product']!),
                      _StickerLine(label: 'Variety', value: args['variety']!),
                      _StickerLine(label: 'Farm', value: args['farmName']!),
                      _StickerLine(label: 'Village', value: args['village']!),
                      _StickerLine(label: 'Farmer', value: args['farmerName']!),
                      _StickerLine(label: 'Farmer ID', value: args['farmerId']!),
                      _StickerLine(label: 'Moisture', value: '${args['moisture']}%'),
                      _StickerLine(
                        label: 'Location',
                        value: '${args['farmLatitude']}, ${args['farmLongitude']}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
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

class _GradeSeal extends StatelessWidget {
  final String grade;

  const _GradeSeal({required this.grade});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: const BoxDecoration(
        color: AppTheme.green,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        grade,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StickerLine extends StatelessWidget {
  final String label;
  final String value;

  const _StickerLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
            maxLines: 1,
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
