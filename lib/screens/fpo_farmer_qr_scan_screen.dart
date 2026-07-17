import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import '../services/fpc_procurement_service.dart';
import '../services/fpc_preferences_service.dart';
import '../widgets/fpc_bottom_nav.dart';

class FpoFarmerQrScanScreen extends StatefulWidget {
  const FpoFarmerQrScanScreen({super.key});

  @override
  State<FpoFarmerQrScanScreen> createState() => _FpoFarmerQrScanScreenState();
}

class _FpoFarmerQrScanScreenState extends State<FpoFarmerQrScanScreen> {
  final _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  Map<String, dynamic>? _farmer;
  String? _error;
  bool _scannerVisible = true;
  bool _scanLocked = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanLocked) return;
    final value = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (value == null || value.trim().isEmpty) return;
    _scanLocked = true;
    unawaited(_scanner.stop());
    _scanPayload(value);
  }

  void _scanPayload(String payload) {
    try {
      final farmer = FarmerProfileQrParser.parse(payload);
      setState(() {
        _farmer = farmer;
        _error = null;
        _scannerVisible = false;
      });
      unawaited(FpcPreferences.playScannerFeedbackIfEnabled());
    } catch (error) {
      final message =
          error is FpcProcurementException && error.message.isNotEmpty
          ? error.message
          : UiStrings.t('farmer_qr_scan_failed');
      setState(() {
        _farmer = null;
        _error = message;
        _scanLocked = false;
      });
    }
  }

  Future<void> _restartScanner() async {
    setState(() {
      _scannerVisible = true;
      _scanLocked = false;
      _error = null;
    });
    await _scanner.start();
  }

  @override
  Widget build(BuildContext context) {
    return FpcWorkspaceScaffold(
      current: FpcNavTab.farmerScan,
      title: UiStrings.t('scan_farmer_qr'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 128),
        children: [
          _ScannerCard(
            controller: _scanner,
            scannerVisible: _scannerVisible,
            onDetect: _onDetect,
            onRestart: _restartScanner,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _ScanError(message: _error!, onRetry: _restartScanner),
          ],
          if (_farmer != null) ...[
            const SizedBox(height: 16),
            _FarmerResultCard(farmer: _farmer!),
          ],
        ],
      ),
    );
  }
}

class _ScannerCard extends StatelessWidget {
  final MobileScannerController controller;
  final bool scannerVisible;
  final void Function(BarcodeCapture capture) onDetect;
  final Future<void> Function() onRestart;

  const _ScannerCard({
    required this.controller,
    required this.scannerVisible,
    required this.onDetect,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            UiStrings.t('fpc_farmer_verification'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            UiStrings.t('fpc_farmer_verification_desc'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: scannerVisible
                ? ClipRRect(
                    key: const ValueKey('scanner'),
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MobileScanner(
                            controller: controller,
                            onDetect: onDetect,
                          ),
                          const _ScannerFrame(),
                        ],
                      ),
                    ),
                  )
                : OutlinedButton.icon(
                    key: const ValueKey('restart'),
                    onPressed: onRestart,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(UiStrings.t('open_camera_scanner')),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ScannerFrame extends StatelessWidget {
  const _ScannerFrame();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(38),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white, width: 3),
        ),
        child: const Center(
          child: Icon(Icons.qr_code_2_rounded, color: Colors.white70, size: 56),
        ),
      ),
    );
  }
}

class _ScanError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ScanError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFE07800)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFC45F00),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(UiStrings.t('scan_again')),
          ),
        ],
      ),
    );
  }
}

class _FarmerResultCard extends StatelessWidget {
  final Map<String, dynamic> farmer;

  const _FarmerResultCard({required this.farmer});

  @override
  Widget build(BuildContext context) {
    final currentCrop = _mapValue(farmer['currentCrop']);
    final production = _listValue(farmer['productionHistory']);
    final sales = _listValue(farmer['sellingHistory']);
    final crop = _text(currentCrop, 'crop', _text(farmer, 'crop'));
    final variety = _text(currentCrop, 'variety', _text(farmer, 'variety'));
    final grade = _text(farmer, 'lastGrade', _text(currentCrop, 'grade'));
    final yield = _text(
      farmer,
      'lastYield',
      _text(currentCrop, 'expectedYield'),
    );
    final rating = _text(farmer, 'fpcRating', UiStrings.t('not_rated'));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.person_rounded,
                  color: AppTheme.green,
                  size: 34,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      UiStrings.label(
                        _text(farmer, 'farmerName', UiStrings.t('role_farmer')),
                      ),
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _text(farmer, 'farmerId'),
                      style: const TextStyle(
                        color: AppTheme.greenDark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.verified_rounded, color: AppTheme.green),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _MetricBox(label: UiStrings.t('rating'), value: rating),
              _MetricBox(label: UiStrings.t('yield'), value: yield),
              _MetricBox(label: UiStrings.t('grade'), value: grade),
            ],
          ),
          const SizedBox(height: 16),
          _ResultRow(
            label: UiStrings.t('phone'),
            value: _text(farmer, 'phone'),
          ),
          _ResultRow(
            label: UiStrings.t('village'),
            value: _text(farmer, 'village'),
          ),
          _ResultRow(
            label: UiStrings.t('primary_farm'),
            value: _text(farmer, 'primaryFarm'),
          ),
          _ResultRow(label: UiStrings.t('area'), value: _text(farmer, 'area')),
          _ResultRow(
            label: UiStrings.t('detail'),
            value: _text(farmer, 'detail'),
          ),
          const SizedBox(height: 12),
          _DetailSection(
            title: UiStrings.t('current_crop'),
            rows: [
              _ResultRow(label: UiStrings.t('crop'), value: crop),
              _ResultRow(label: UiStrings.t('variety'), value: variety),
              _ResultRow(
                label: UiStrings.t('season'),
                value: _text(currentCrop, 'season', UiStrings.t('current')),
              ),
              _ResultRow(
                label: UiStrings.t('expected_yield'),
                value: _text(currentCrop, 'expectedYield', yield),
              ),
              _ResultRow(
                label: UiStrings.t('grade'),
                value: _text(currentCrop, 'grade', grade),
              ),
              _ResultRow(
                label: UiStrings.t('detail'),
                value: _text(currentCrop, 'detail'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _HistorySection(
            title: UiStrings.t('past_crop_production'),
            emptyText: UiStrings.t('no_past_crop_production_qr'),
            rows: production,
            fields: const ['season', 'crop', 'yield', 'grade', 'detail'],
          ),
          const SizedBox(height: 12),
          _HistorySection(
            title: UiStrings.t('selling_history'),
            emptyText: UiStrings.t('no_selling_history_qr'),
            rows: sales,
            fields: const ['date', 'buyer', 'quantity', 'rate', 'rating'],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Get.snackbar(
                    UiStrings.t('farmer_linked'),
                    UiStrings.t('farmer_profile_verified_fpo'),
                    snackPosition: SnackPosition.BOTTOM,
                  ),
                  icon: const Icon(Icons.group_add_outlined),
                  label: Text(UiStrings.t('add_to_fpc_records')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Get.toNamed(
                    '/fpo/grain-grading',
                    arguments: _gradingArgs(farmer),
                  ),
                  icon: const Icon(Icons.grain_rounded),
                  label: Text(UiStrings.t('grade_lot')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Map<String, dynamic> _gradingArgs(Map<String, dynamic> farmer) {
    final currentCrop = _mapValue(farmer['currentCrop']);
    final farmerId = _text(farmer, 'farmerId');
    final farmerName = _text(farmer, 'farmerName', UiStrings.t('fpc_customer'));
    return {
      'mode': 'fpc',
      'farmerId': farmerId,
      'farmerName': farmerName,
      'fpcCustomerId': _text(
        farmer,
        'fpcCustomerId',
        farmerId.isEmpty ? 'FPC-CUSTOMER' : farmerId,
      ),
      'fpcCustomerName': farmerName,
      'farmId': _text(farmer, 'farmId', farmerId),
      'farmName': _text(
        farmer,
        'primaryFarm',
        UiStrings.t('fpc_customer_farm'),
      ),
      'crop': _text(
        currentCrop,
        'crop',
        _text(farmer, 'crop', 'Finger Millet'),
      ),
      'variety': _text(
        currentCrop,
        'variety',
        _text(farmer, 'variety', 'Local'),
      ),
      'village': _text(farmer, 'village'),
      'product': _text(farmer, 'product'),
    };
  }
}

class _MetricBox extends StatelessWidget {
  final String label;
  final String value;

  const _MetricBox({required this.label, required this.value});

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
              UiStrings.label(value),
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

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> rows;

  const _DetailSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.greenPale.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  final String title;
  final String emptyText;
  final List<Map<String, dynamic>> rows;
  final List<String> fields;

  const _HistorySection({
    required this.title,
    required this.emptyText,
    required this.rows,
    required this.fields,
  });

  @override
  Widget build(BuildContext context) {
    return _DetailSection(
      title: title,
      rows: rows.isEmpty
          ? [
              Text(
                emptyText,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ]
          : rows
                .map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fields
                              .take(2)
                              .map((field) => _text(row, field))
                              .where((value) => value != '--')
                              .map(UiStrings.label)
                              .join(' - '),
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          fields
                              .skip(2)
                              .map((field) => _text(row, field))
                              .where((value) => value != '--')
                              .map(UiStrings.label)
                              .join(' - '),
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;

  const _ResultRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
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

Map<String, dynamic> _mapValue(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const {};
}

List<Map<String, dynamic>> _listValue(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

String _text(
  Map<String, dynamic> source,
  String key, [
  String fallback = '--',
]) {
  final value = source[key];
  final text = value == null ? '' : '$value'.trim();
  return text.isEmpty ? fallback : text;
}
