import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';

class FpoFarmerQrScanScreen extends StatefulWidget {
  const FpoFarmerQrScanScreen({super.key});

  @override
  State<FpoFarmerQrScanScreen> createState() => _FpoFarmerQrScanScreenState();
}

class _FpoFarmerQrScanScreenState extends State<FpoFarmerQrScanScreen> {
  final _payloadCtrl = TextEditingController();
  Map<String, dynamic>? _farmer;
  String? _error;

  static const _samplePayload = {
    'type': 'farmer_profile',
    'allowedRole': 'fpo_fpc',
    'brand': 'Kalsubai Farms',
    'farmerId': 'FMR-2026-001',
    'farmerName': 'Santosh Pawar',
    'phone': '+91 98765 43210',
    'village': 'Rajur, Akole',
    'primaryFarm': 'Rajur Millet Plot',
    'crop': 'Finger Millet',
    'area': '2.4 acres',
    'verified': true,
  };

  @override
  void dispose() {
    _payloadCtrl.dispose();
    super.dispose();
  }

  void _scanPayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid farmer QR.');
      }
      if (decoded['type'] != 'farmer_profile' ||
          decoded['allowedRole'] != 'fpo_fpc') {
        throw const FormatException('This QR is not for FPO / FPC access.');
      }
      setState(() {
        _farmer = decoded;
        _error = null;
      });
    } catch (_) {
      setState(() {
        _farmer = null;
        _error = 'Scan failed. Use a valid Kalsubai Farms farmer QR.';
      });
    }
  }

  void _scanDemoQr() {
    final payload = jsonEncode(_samplePayload);
    _payloadCtrl.text = payload;
    _scanPayload(payload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Scan Farmer QR')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanDemoQr,
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Scan sample'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 96),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: AppTheme.green,
                  size: 56,
                ),
                const SizedBox(height: 12),
                const Text(
                  'FPO / FPC Farmer Verification',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Scan the farmer profile QR from the farmer app profile section.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _payloadCtrl,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'QR payload',
                    hintText: 'Paste farmer QR payload for verification',
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _scanPayload(_payloadCtrl.text.trim()),
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Verify farmer'),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _ScanError(message: _error!),
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

class _ScanError extends StatelessWidget {
  final String message;

  const _ScanError({required this.message});

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
                      '${farmer['farmerName'] ?? 'Farmer'}',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${farmer['farmerId'] ?? '-'}',
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
          const SizedBox(height: 18),
          _ResultRow(label: 'Phone', value: '${farmer['phone'] ?? '-'}'),
          _ResultRow(label: 'Village', value: '${farmer['village'] ?? '-'}'),
          _ResultRow(
            label: 'Primary Farm',
            value: '${farmer['primaryFarm'] ?? '-'}',
          ),
          _ResultRow(label: 'Crop', value: '${farmer['crop'] ?? '-'}'),
          _ResultRow(label: 'Area', value: '${farmer['area'] ?? '-'}'),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Get.snackbar(
                'Farmer linked',
                'Farmer profile is verified for FPO / FPC access.',
                snackPosition: SnackPosition.BOTTOM,
              ),
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Add to FPO records'),
            ),
          ),
        ],
      ),
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
        children: [
          SizedBox(
            width: 104,
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
