import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../config/theme.dart';
import '../widgets/fpc_bottom_nav.dart';

class FpoFarmerQrScanScreen extends StatefulWidget {
  const FpoFarmerQrScanScreen({super.key});

  @override
  State<FpoFarmerQrScanScreen> createState() => _FpoFarmerQrScanScreenState();
}

class _FpoFarmerQrScanScreenState extends State<FpoFarmerQrScanScreen> {
  final _payloadCtrl = TextEditingController();
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
    _payloadCtrl.dispose();
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanLocked) return;
    final value = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (value == null || value.trim().isEmpty) return;
    _scanLocked = true;
    unawaited(_scanner.stop());
    _payloadCtrl.text = value;
    _scanPayload(value, fromCamera: true);
  }

  void _scanPayload(String payload, {bool fromCamera = false}) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        throw const FormatException('Invalid farmer QR.');
      }
      final farmer = Map<String, dynamic>.from(decoded);
      if (farmer['type'] != 'farmer_profile' ||
          farmer['allowedRole'] != 'fpo_fpc') {
        throw const FormatException('This QR is not for FPO / FPC access.');
      }
      setState(() {
        _farmer = farmer;
        _error = null;
        _scannerVisible = false;
      });
    } catch (_) {
      setState(() {
        _farmer = null;
        _error = 'Scan failed. Use a valid Kalsubai Farms farmer QR.';
        if (!fromCamera) _scanLocked = false;
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
    return Scaffold(
      backgroundColor: AppTheme.surface,
      extendBody: true,
      bottomNavigationBar: const FpcBottomNavBar(current: FpcNavTab.farmerScan),
      appBar: AppBar(title: const Text('Scan Farmer QR')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 128),
        children: [
          _ScannerCard(
            controller: _scanner,
            scannerVisible: _scannerVisible,
            onDetect: _onDetect,
            onRestart: _restartScanner,
            payloadController: _payloadCtrl,
            onVerify: () => _scanPayload(_payloadCtrl.text.trim()),
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
  final TextEditingController payloadController;
  final VoidCallback onVerify;

  const _ScannerCard({
    required this.controller,
    required this.scannerVisible,
    required this.onDetect,
    required this.onRestart,
    required this.payloadController,
    required this.onVerify,
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
          const Text(
            'FPC Farmer Verification',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Use this FPC login scanner for farmer passport/profile QR only.',
            textAlign: TextAlign.center,
            style: TextStyle(
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
                    label: const Text('Open camera scanner'),
                  ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: payloadController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'QR payload',
              hintText: 'Paste farmer QR payload for verification',
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onVerify,
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Verify farmer'),
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
          TextButton(onPressed: onRetry, child: const Text('Scan again')),
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
    final yield = _text(farmer, 'lastYield', _text(currentCrop, 'expectedYield'));
    final rating = _text(farmer, 'fpcRating', 'Not rated');

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
                      _text(farmer, 'farmerName', 'Farmer'),
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
              _MetricBox(label: 'Rating', value: rating),
              _MetricBox(label: 'Yield', value: yield),
              _MetricBox(label: 'Grade', value: grade),
            ],
          ),
          const SizedBox(height: 16),
          _ResultRow(label: 'Phone', value: _text(farmer, 'phone')),
          _ResultRow(label: 'Village', value: _text(farmer, 'village')),
          _ResultRow(label: 'Primary Farm', value: _text(farmer, 'primaryFarm')),
          _ResultRow(label: 'Area', value: _text(farmer, 'area')),
          _ResultRow(label: 'Detail', value: _text(farmer, 'detail')),
          const SizedBox(height: 12),
          _DetailSection(
            title: 'Current Crop',
            rows: [
              _ResultRow(label: 'Crop', value: crop),
              _ResultRow(label: 'Variety', value: variety),
              _ResultRow(
                label: 'Season',
                value: _text(currentCrop, 'season', 'Current'),
              ),
              _ResultRow(
                label: 'Expected Yield',
                value: _text(currentCrop, 'expectedYield', yield),
              ),
              _ResultRow(label: 'Grade', value: _text(currentCrop, 'grade', grade)),
              _ResultRow(label: 'Detail', value: _text(currentCrop, 'detail')),
            ],
          ),
          const SizedBox(height: 12),
          _HistorySection(
            title: 'Past Crop Production',
            emptyText: 'No past crop production captured in this QR.',
            rows: production,
            fields: const ['season', 'crop', 'yield', 'grade', 'detail'],
          ),
          const SizedBox(height: 12),
          _HistorySection(
            title: 'Selling History',
            emptyText: 'No selling history captured in this QR.',
            rows: sales,
            fields: const ['date', 'buyer', 'quantity', 'rate', 'rating'],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Get.snackbar(
                    'Farmer linked',
                    'Farmer profile is verified for FPO / FPC access.',
                    snackPosition: SnackPosition.BOTTOM,
                  ),
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Add to FPC records'),
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
                  label: const Text('Grade lot'),
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
    final farmerName = _text(farmer, 'farmerName', 'FPC customer');
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
      'farmName': _text(farmer, 'primaryFarm', 'FPC customer farm'),
      'crop': _text(currentCrop, 'crop', _text(farmer, 'crop', 'Finger Millet')),
      'variety': _text(currentCrop, 'variety', _text(farmer, 'variety', 'Local')),
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

String _text(Map<String, dynamic> source, String key, [String fallback = '--']) {
  final value = source[key];
  final text = value == null ? '' : '$value'.trim();
  return text.isEmpty ? fallback : text;
}
