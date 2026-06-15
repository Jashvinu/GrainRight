import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/brand_assets.dart';
import '../config/theme.dart';

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
      appBar: AppBar(title: const Text('Harvest Trace')),
      body: trace == null
          ? const _TraceError()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              children: [
                _TraceHero(trace: trace),
                const SizedBox(height: 14),
                _TraceSection(
                  title: 'Lot Details',
                  rows: [
                    _TraceRow('Batch', _text(trace, 'batchId')),
                    _TraceRow('Analysis ID', _text(trace, 'analysisId')),
                    _TraceRow('Crop', _text(trace, 'crop')),
                    _TraceRow('Variety', _text(trace, 'variety')),
                    _TraceRow('Product', _text(trace, 'product')),
                    _TraceRow('Quantity', _quantity(trace)),
                  ],
                ),
                const SizedBox(height: 12),
                _TraceSection(
                  title: 'Farm Source',
                  rows: [
                    _TraceRow('Farm', _text(trace, 'farm')),
                    _TraceRow('Farm ID', _text(trace, 'farmId')),
                    _TraceRow('Village', _text(trace, 'village')),
                    _TraceRow('Farmer', _text(trace, 'farmerName')),
                    _TraceRow('Farmer ID', _text(trace, 'farmerId')),
                    _TraceRow('Location', _location(trace)),
                  ],
                ),
                const SizedBox(height: 12),
                _TraceSection(
                  title: 'Quality',
                  rows: [
                    _TraceRow('Grade', _text(trace, 'grade')),
                    _TraceRow('Score', _score(trace)),
                    _TraceRow('Moisture', _percent(trace, 'moisture')),
                    _TraceRow('Moisture Source', _text(trace, 'moistureSource')),
                    _TraceRow('Standards', _text(trace, 'standards')),
                    _TraceRow('Grader', _text(trace, 'grader')),
                    _TraceRow('Review', _text(trace, 'reviewStatus')),
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
    return '$total kg ($bags bags x $bagSize kg)';
  }

  static String _score(Map<String, dynamic> trace) {
    final score = _text(trace, 'score');
    if (score == '--') return score;
    return score.contains('/') ? score : '$score/100';
  }

  static String _location(Map<String, dynamic> trace) {
    final lat = _text(trace, 'farmLatitude');
    final lng = _text(trace, 'farmLongitude');
    if (lat == '--' || lng == '--') return '--';
    return '$lat, $lng';
  }

  static String _percent(Map<String, dynamic> trace, String key) {
    final value = _text(trace, key);
    if (value == '--') return value;
    return value.endsWith('%') ? value : '$value%';
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
          Image.asset(BrandAssets.logo, width: 52, height: 52),
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
              value,
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
              'Trace verified at $verifiedAt',
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
          children: const [
            Icon(Icons.qr_code_2_rounded, size: 72, color: AppTheme.textMuted),
            SizedBox(height: 16),
            Text(
              'Invalid trace code',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 8),
            Text(
              'Scan a valid Kalsubai Farms harvest QR sticker.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
