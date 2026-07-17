import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:kalsubai_farms/core/config/brand_assets.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';

class PublicTraceScreen extends StatelessWidget {
  const PublicTraceScreen({super.key});

  Map<String, dynamic>? _trace() {
    final token = Get.parameters['token'] ?? '';
    if (token.trim().isEmpty) return null;
    try {
      final normalized = _padBase64(token.trim());
      final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  static String _padBase64(String value) {
    final remainder = value.length % 4;
    if (remainder == 0) return value;
    return value.padRight(value.length + 4 - remainder, '=');
  }

  @override
  Widget build(BuildContext context) {
    final trace = _trace();
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        title: Text(UiStrings.t('harvest_trace')),
      ),
      body: trace == null
          ? const _TraceError()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              children: [
                _TraceHero(trace: trace),
                const SizedBox(height: 14),
                _TraceSection(
                  title: UiStrings.t('lot_details'),
                  rows: [
                    _TraceRow(UiStrings.t('batch'), _text(trace, 'batchId')),
                    _TraceRow(UiStrings.t('analysis_id'), _text(trace, 'analysisId')),
                    _TraceRow(UiStrings.t('crop'), _text(trace, 'crop')),
                    _TraceRow(UiStrings.t('variety'), _text(trace, 'variety')),
                    _TraceRow(UiStrings.t('product'), _text(trace, 'product')),
                    _TraceRow(UiStrings.t('quantity'), _quantity(trace)),
                  ],
                ),
                const SizedBox(height: 12),
                _TraceSection(
                  title: UiStrings.t('farm_source'),
                  rows: [
                    _TraceRow(UiStrings.t('farm_label'), _text(trace, 'farm')),
                    _TraceRow(UiStrings.t('farm_id_label'), _text(trace, 'farmId')),
                    _TraceRow(UiStrings.t('village'), _text(trace, 'village')),
                    _TraceRow(UiStrings.t('role_farmer'), _text(trace, 'farmerName')),
                    _TraceRow(UiStrings.t('farmer_id_label'), _text(trace, 'farmerId')),
                    _TraceRow(UiStrings.t('location'), _location(trace)),
                  ],
                ),
                const SizedBox(height: 12),
                _TraceSection(
                  title: UiStrings.t('quality'),
                  rows: [
                    _TraceRow(UiStrings.t('grade'), _text(trace, 'grade')),
                    _TraceRow(UiStrings.t('score'), _score(trace)),
                    _TraceRow(UiStrings.t('moisture'), _percent(trace, 'moisture')),
                    _TraceRow(UiStrings.t('moisture_source'), _text(trace, 'moistureSource')),
                    _TraceRow(UiStrings.t('standards'), _text(trace, 'standards')),
                    _TraceRow(UiStrings.t('grader'), _text(trace, 'grader')),
                    _TraceRow(UiStrings.t('review'), _text(trace, 'reviewStatus')),
                  ],
                ),
                const SizedBox(height: 12),
                _VerifiedBanner(verifiedAt: _verifiedAt(trace)),
              ],
            ),
    );
  }

  static String _text(Map<String, dynamic> trace, String key) {
    final value = trace[key];
    final text = value == null ? '' : '$value'.trim();
    return text.isEmpty ? '--' : text;
  }

  static String _quantity(Map<String, dynamic> trace) {
    final total = _text(trace, 'totalKg');
    final bags = _text(trace, 'bagCount');
    final bagSize = _text(trace, 'bagSizeKg');
    if (total == '--') return '--';
    return UiStrings.f('trace_quantity_bags', {
      'total': total,
      'bags': bags,
      'bagSize': bagSize,
    });
  }

  static String _score(Map<String, dynamic> trace) {
    final score = _text(trace, 'score');
    if (score == '--') return score;
    return score.contains('/')
        ? UiStrings.label(score)
        : UiStrings.f('score_out_of_100', {'score': score});
  }

  static String _location(Map<String, dynamic> trace) {
    final lat = _text(trace, 'farmLatitude');
    final lng = _text(trace, 'farmLongitude');
    if (lat == '--' || lng == '--') return '--';
    return UiStrings.f('lat_lng_value', {'lat': lat, 'lng': lng});
  }

  static String _percent(Map<String, dynamic> trace, String key) {
    final value = _text(trace, key);
    if (value == '--') return value;
    return value.endsWith('%')
        ? UiStrings.label(value)
        : UiStrings.f('percent_value', {'value': value});
  }

  static String _verifiedAt(Map<String, dynamic> trace) {
    final generated = _text(trace, 'generatedAt');
    return generated == '--' ? _text(trace, 'verifiedAt') : generated;
  }
}

class _TraceHero extends StatelessWidget {
  final Map<String, dynamic> trace;

  const _TraceHero({required this.trace});

  @override
  Widget build(BuildContext context) {
    final grade = PublicTraceScreen._text(trace, 'grade');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Image.asset(
            BrandAssets.logo,
            width: 52,
            height: 52,
            cacheWidth: 156,
          ),
          const SizedBox(width: 14),
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
                const SizedBox(height: 4),
                Text(
                  PublicTraceScreen._text(trace, 'batchId'),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 58,
            height: 58,
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
          ),
        ],
      ),
    );
  }
}

class _TraceSection extends StatelessWidget {
  final String title;
  final List<_TraceRow> rows;

  const _TraceSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    );
  }
}

class _TraceRow extends StatelessWidget {
  final String label;
  final String value;

  const _TraceRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              UiStrings.label(value),
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifiedBanner extends StatelessWidget {
  final String verifiedAt;

  const _VerifiedBanner({required this.verifiedAt});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: AppTheme.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              UiStrings.f('trace_verified_at', {'value': verifiedAt}),
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TraceError extends StatelessWidget {
  const _TraceError();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2_rounded, size: 72, color: AppTheme.textMuted),
            const SizedBox(height: 16),
            Text(
              UiStrings.t('invalid_trace_code'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              UiStrings.t('scan_valid_harvest_qr'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
