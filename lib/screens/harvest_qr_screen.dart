import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:kalsubai_farms/core/config/brand_assets.dart';
import '../config/runtime_config.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/locale_text.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import '../utils/harvest_sticker_downloader.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';

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
      String value(String key, [String fallback = '']) {
        return '${args[key] ?? fallback}'.trim();
      }

      return {
        'farmName': value('farmName'),
        'farmId': value('farmId'),
        'analysisId': value('analysisId'),
        'crop': value('crop'),
        'product': value('product'),
        'variety': value('variety'),
        'village': value('village'),
        'farmerName': value('farmerName'),
        'farmerId': value('farmerId'),
        'grade': value('grade'),
        'score': value('score'),
        'standards': value('standards'),
        'bagSizeKg': value('bagSizeKg'),
        'bagCount': value('bagCount'),
        'totalKg': value('totalKg'),
        'moisture': value('moisture'),
        'moistureSource': value('moistureSource'),
        'farmLatitude': value('farmLatitude'),
        'farmLongitude': value('farmLongitude'),
        'grader': value('grader'),
        'batchId': value('batchId'),
        'reviewStatus': value('reviewStatus', 'not_required'),
        'actorRole': value('actorRole', 'farmer'),
        'fpcCustomerId': value('fpcCustomerId'),
        'fpcCustomerName': value('fpcCustomerName'),
      };
    }
    return const {
      'farmName': '',
      'farmId': '',
      'analysisId': '',
      'crop': '',
      'product': '',
      'variety': '',
      'village': '',
      'farmerName': '',
      'farmerId': '',
      'grade': '',
      'score': '',
      'standards': '',
      'bagSizeKg': '',
      'bagCount': '',
      'totalKg': '',
      'moisture': '',
      'moistureSource': '',
      'farmLatitude': '',
      'farmLongitude': '',
      'grader': '',
      'batchId': '',
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

    if (empty('analysisId')) missing.add(UiStrings.t('complete_grading'));
    if (empty('farmerId')) missing.add(UiStrings.t('complete_farmer_profile'));
    if (empty('farmId')) missing.add(UiStrings.t('select_saved_farm'));
    if (empty('batchId')) missing.add(UiStrings.t('add_batch_id'));
    if (empty('bagSizeKg') || empty('bagCount') || empty('totalKg')) {
      missing.add(UiStrings.t('add_bag_details'));
    }
    if (empty('moisture')) missing.add(UiStrings.t('confirm_moisture'));
    if (empty('grade')) missing.add(UiStrings.t('complete_grade_result'));
    final review = (a['reviewStatus'] ?? '').trim();
    if (review == 'pending' || review == 'missing') {
      missing.add(UiStrings.t('wait_for_fpo_review_approval'));
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
        UiStrings.t('qr_locked'),
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
        UiStrings.t('harvest_sticker_ready'),
        UiStrings.f('saved_to', {'path': savedTo}),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (_) {
      if (!mounted) return;
      Get.snackbar(
        UiStrings.t('download_failed'),
        UiStrings.t('could_not_export_sticker'),
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
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        title: Text(UiStrings.t('harvest_qr')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          if (missingReasons.isNotEmpty) ...[
            _QrLockCard(reasons: missingReasons),
            const SizedBox(height: 12),
          ],
          if (_canGenerate)
            RepaintBoundary(
              key: _stickerKey,
              child: _HarvestStickerCard(args: a, qrData: _qrData),
            )
          else
            const _QrUnavailableCard(),
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
                Text(
                  UiStrings.t('sticker_use'),
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  UiStrings.t('harvest_sticker_desc'),
                  style: TextStyle(color: AppTheme.textMuted, height: 1.45),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isDownloading || !_canGenerate
                      ? null
                      : _downloadSticker,
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
                    _isDownloading
                        ? UiStrings.t('preparing')
                        : UiStrings.t('download_sticker'),
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
                Text(
                  UiStrings.t('qr_locked'),
                  style: const TextStyle(
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

class _QrUnavailableCard extends StatelessWidget {
  const _QrUnavailableCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.qr_code_2_rounded,
            size: 58,
            color: AppTheme.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            UiStrings.t('harvest_qr_inputs_required_title'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            UiStrings.t('harvest_qr_inputs_required_body'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textMuted,
              height: 1.35,
              fontWeight: FontWeight.w700,
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
              Image.asset(
                BrandAssets.logo,
                width: 48,
                height: 48,
                cacheWidth: 144,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Kalsubai Farms',
                      style: TextStyle(
                        color: AppTheme.greenDark,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      UiStrings.t('harvest_trace_sticker'),
                      style: const TextStyle(
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
                        children: [qrBox, const SizedBox(height: 12), summary],
                      ),
              );
            },
          ),
          const SizedBox(height: 14),
          _StickerDetailGrid(
            details: [
              _StickerDetail(
                label: UiStrings.t('batch'),
                value: args['batchId']!,
              ),
              _StickerDetail(
                label: UiStrings.t('analysis_id'),
                value: args['analysisId']!,
              ),
              _StickerDetail(
                label: UiStrings.t('crop'),
                value: _localizedHarvestValue(args['crop']),
              ),
              _StickerDetail(
                label: UiStrings.t('product'),
                value: _localizedHarvestValue(args['product']),
              ),
              _StickerDetail(
                label: UiStrings.t('variety'),
                value: _localizedHarvestValue(args['variety']),
              ),
              _StickerDetail(
                label: UiStrings.t('farm'),
                value: _localizedHarvestValue(args['farmName']),
              ),
              _StickerDetail(
                label: UiStrings.t('farm_id'),
                value: args['farmId']!,
              ),
              _StickerDetail(
                label: UiStrings.t('village'),
                value: _localizedHarvestValue(args['village']),
              ),
              _StickerDetail(
                label: UiStrings.t('farmer'),
                value: _localizedHarvestValue(args['farmerName']),
              ),
              _StickerDetail(
                label: UiStrings.t('farmer_id'),
                value: args['farmerId']!,
              ),
              _StickerDetail(
                label: UiStrings.t('moisture'),
                value: _withPercent(args['moisture']!),
              ),
              _StickerDetail(
                label: UiStrings.t('location'),
                value:
                    '${LocaleText.digits(args['farmLatitude']!)} , ${LocaleText.digits(args['farmLongitude']!)}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StickerMetric(
                label: UiStrings.t('bag_size'),
                value:
                    '${LocaleText.digits(args['bagSizeKg']!)} ${UiStrings.t('kg_unit')}',
              ),
              _StickerMetric(
                label: UiStrings.t('bags_label'),
                value: LocaleText.digits(args['bagCount']!),
              ),
              _StickerMetric(
                label: UiStrings.t('total'),
                value:
                    '${LocaleText.digits(args['totalKg']!)} ${UiStrings.t('kg_unit')}',
              ),
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
              '${UiStrings.t('grade')} ${_localizedHarvestValue(args['grade'])} • ${UiStrings.t('score')} ${LocaleText.digits(args['score']!)}/100 • ${_localizedHarvestValue(args['standards'])} • ${_localizedHarvestValue(args['grader'])}',
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
          Text(
            UiStrings.t('scan_harvest_qr'),
            textAlign: TextAlign.center,
            style: const TextStyle(
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
          Text(
            UiStrings.t('grade'),
            style: const TextStyle(
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
              _localizedHarvestValue(args['grade']),
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 54,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _StickerSummaryLine(
            label: UiStrings.t('location'),
            value: _harvestLocation(args),
          ),
          _StickerSummaryLine(
            label: UiStrings.t('harvest_yield'),
            value: _yieldLabel(args),
          ),
          _StickerSummaryLine(
            label: UiStrings.t('rating'),
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
  if (village.isNotEmpty && village != '--') {
    return _localizedHarvestValue(village);
  }
  final lat = (args['farmLatitude'] ?? '').trim();
  final lng = (args['farmLongitude'] ?? '').trim();
  if (lat.isEmpty || lng.isEmpty || lat == '--' || lng == '--') return '--';
  return '${LocaleText.digits(lat)}, ${LocaleText.digits(lng)}';
}

String _yieldLabel(Map<String, String> args) {
  final total = (args['totalKg'] ?? '').trim();
  final bags = (args['bagCount'] ?? '').trim();
  if (total.isEmpty || total == '--') return '--';
  final totalLabel = total.toLowerCase().contains('kg')
      ? LocaleText.digits(total)
      : '${LocaleText.digits(total)} ${UiStrings.t('kg_unit')}';
  if (bags.isEmpty || bags == '--') return totalLabel;
  return '$totalLabel / ${LocaleText.digits(bags)} ${UiStrings.t('bags_label')}';
}

String _ratingLabel(Map<String, String> args) {
  final score = (args['score'] ?? '').trim();
  if (score.isEmpty || score == '--') return '--';
  return score.contains('/')
      ? LocaleText.digits(score)
      : '${LocaleText.digits(score)}/100';
}

String _localizedHarvestValue(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return '--';
  final normalized = text.toLowerCase();
  return switch (normalized) {
    'finger millet' => UiStrings.option(text),
    'foxtail millet' => UiStrings.option(text),
    'little millet' => UiStrings.option(text),
    'kodo millet' => UiStrings.option(text),
    'pearl millet' => UiStrings.option(text),
    'millet' => UiStrings.t('millet'),
    'pending' => UiStrings.t('review_pending'),
    'microservice' => UiStrings.t('microservice'),
    'farmer' => UiStrings.t('farmer'),
    'unknown' => '--',
    _ => LocaleText.digits(text),
  };
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
  if (trimmed.isEmpty || trimmed == '--') {
    return trimmed.isEmpty ? '--' : trimmed;
  }
  return trimmed.endsWith('%')
      ? LocaleText.digits(trimmed)
      : '${LocaleText.digits(trimmed)}%';
}
