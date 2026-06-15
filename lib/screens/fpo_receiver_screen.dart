import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../config/theme.dart';
import '../services/fpc_procurement_service.dart';
import '../widgets/fpc_bottom_nav.dart';

class FpoReceiverScreen extends StatefulWidget {
  const FpoReceiverScreen({super.key});

  @override
  State<FpoReceiverScreen> createState() => _FpoReceiverScreenState();
}

class _FpoReceiverScreenState extends State<FpoReceiverScreen> {
  final _service = FpcProcurementService();
  final _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final _priceCtrl = TextEditingController();
  final _ratingCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  Map<String, dynamic>? _trace;
  List<FpcProcurementRecord> _records = const [];
  bool _scannerVisible = true;
  bool _scanLocked = false;
  bool _loadingRecords = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecords());
  }

  @override
  void dispose() {
    _scanner.dispose();
    _priceCtrl.dispose();
    _ratingCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    setState(() => _loadingRecords = true);
    try {
      final records = await _service.fetchRecords();
      if (!mounted) return;
      setState(() {
        _records = records;
        _loadingRecords = false;
      });
    } on FpcProcurementException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loadingRecords = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load received product records.';
        _loadingRecords = false;
      });
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanLocked) return;
    final value = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (value == null || value.trim().isEmpty) return;
    _scanLocked = true;
    unawaited(_scanner.stop());
    _readHarvestQr(value);
  }

  void _readHarvestQr(String raw) {
    try {
      final trace = HarvestTraceParser.parse(raw);
      setState(() {
        _trace = trace;
        _error = null;
        _scannerVisible = false;
      });
    } on FpcProcurementException catch (e) {
      setState(() {
        _trace = null;
        _error = e.message;
        _scanLocked = false;
      });
    } catch (_) {
      setState(() {
        _trace = null;
        _error = 'Could not read this harvest QR.';
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

  Future<void> _saveReceivedLot() async {
    final trace = _trace;
    if (trace == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await _service.saveHarvestTrace(
        trace: trace,
        pricePerKg: _toDouble(_priceCtrl.text),
        fpcRating: int.tryParse(_ratingCtrl.text.trim()),
        notes: _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _records = [
          saved,
          ..._records.where((record) => record.id != saved.id),
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Received lot ${saved.batchId} saved.')),
      );
    } on FpcProcurementException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save received product in remote database.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      extendBody: true,
      bottomNavigationBar: const FpcBottomNavBar(current: FpcNavTab.receiver),
      appBar: AppBar(title: const Text('FPC Receiver')),
      body: RefreshIndicator(
        onRefresh: _loadRecords,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 128),
          children: [
            _ReceiverScannerCard(
              controller: _scanner,
              scannerVisible: _scannerVisible,
              onDetect: _onDetect,
              onRestart: _restartScanner,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ReceiverError(message: _error!),
            ],
            if (_trace != null) ...[
              const SizedBox(height: 14),
              _TraceReceiveCard(
                trace: _trace!,
                priceController: _priceCtrl,
                ratingController: _ratingCtrl,
                notesController: _notesCtrl,
                saving: _saving,
                onSave: _saveReceivedLot,
              ),
            ],
            const SizedBox(height: 18),
            _ReceiverLedger(records: _records, loading: _loadingRecords),
          ],
        ),
      ),
    );
  }
}

class _ReceiverScannerCard extends StatelessWidget {
  final MobileScannerController controller;
  final bool scannerVisible;
  final void Function(BarcodeCapture capture) onDetect;
  final Future<void> Function() onRestart;

  const _ReceiverScannerCard({
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
          const Text(
            'Receive Harvest Lot',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scan a public harvest QR sticker. The received product is saved to the FPC remote ledger.',
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
                    key: const ValueKey('receiver-scanner'),
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
                    key: const ValueKey('receiver-restart'),
                    onPressed: onRestart,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Scan another harvest QR'),
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
          child: Icon(Icons.inventory_2_rounded, color: Colors.white70, size: 56),
        ),
      ),
    );
  }
}

class _TraceReceiveCard extends StatelessWidget {
  final Map<String, dynamic> trace;
  final TextEditingController priceController;
  final TextEditingController ratingController;
  final TextEditingController notesController;
  final bool saving;
  final VoidCallback onSave;

  const _TraceReceiveCard({
    required this.trace,
    required this.priceController,
    required this.ratingController,
    required this.notesController,
    required this.saving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final batch = _text(trace, 'batchId', 'Harvest lot');
    final grade = _text(trace, 'grade');
    final score = _scoreLabel(trace);
    final quantity = _quantityLabel(trace);
    final moisture = _percentLabel(trace, 'moisture');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  color: AppTheme.green,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  grade == '--' ? '-' : grade,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      batch,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_text(trace, 'crop')} - ${_text(trace, 'variety')}',
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
          Row(
            children: [
              _ReceiveMetric(label: 'Grade', value: grade),
              _ReceiveMetric(label: 'Score', value: score),
              _ReceiveMetric(label: 'Quantity', value: quantity),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                _ReceiveRow(label: 'Batch ID', value: batch),
                _ReceiveRow(label: 'Analysis ID', value: _text(trace, 'analysisId')),
                _ReceiveRow(label: 'Farmer', value: _text(trace, 'farmerName')),
                _ReceiveRow(label: 'Farmer ID', value: _text(trace, 'farmerId')),
                _ReceiveRow(label: 'Farm', value: _text(trace, 'farm')),
                _ReceiveRow(label: 'Farm ID', value: _text(trace, 'farmId')),
                _ReceiveRow(label: 'Village', value: _text(trace, 'village')),
                _ReceiveRow(label: 'Crop', value: _text(trace, 'crop')),
                _ReceiveRow(label: 'Product', value: _text(trace, 'product')),
                _ReceiveRow(label: 'Variety', value: _text(trace, 'variety')),
                _ReceiveRow(label: 'Bags', value: _bagLabel(trace)),
                _ReceiveRow(label: 'Quantity', value: quantity),
                _ReceiveRow(label: 'Moisture', value: moisture),
                _ReceiveRow(
                  label: 'Moisture source',
                  value: _text(trace, 'moistureSource'),
                ),
                _ReceiveRow(label: 'Standards', value: _text(trace, 'standards')),
                _ReceiveRow(label: 'Grader', value: _text(trace, 'grader')),
                _ReceiveRow(label: 'Review', value: _text(trace, 'reviewStatus')),
                _ReceiveRow(
                  label: 'Trace generated',
                  value: _dateTimeLabel(trace),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Price/kg',
                    prefixIcon: Icon(Icons.currency_rupee),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: ratingController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Rating 1-5',
                    prefixIcon: Icon(Icons.star_border_rounded),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notesController,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Receiver notes',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(saving ? 'Saving' : 'Save received product'),
          ),
        ],
      ),
    );
  }
}

class _ReceiveMetric extends StatelessWidget {
  final String label;
  final String value;

  const _ReceiveMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.greenPale.withValues(alpha: 0.75),
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

class _ReceiverLedger extends StatelessWidget {
  final List<FpcProcurementRecord> records;
  final bool loading;

  const _ReceiverLedger({required this.records, required this.loading});

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
          const Text(
            'Received Products Ledger',
            style: TextStyle(
              color: Colors.black,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (records.isEmpty)
            const Text(
              'No purchased product received yet. Scan harvest QR stickers to create accountability records.',
              style: TextStyle(color: AppTheme.textMuted, height: 1.4),
            )
          else
            ...records.map((record) => _LedgerTile(record: record)),
        ],
      ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  final FpcProcurementRecord record;

  const _LedgerTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final total = record.totalValue == null
        ? '--'
        : 'Rs ${record.totalValue!.toStringAsFixed(0)}';
    final quantity = record.quantityKg == null
        ? '--'
        : '${record.quantityKg!.toStringAsFixed(1)} kg';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppTheme.greenPale,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              record.grade.isEmpty ? '-' : record.grade,
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.batchId.isEmpty ? 'Received lot' : record.batchId,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  '${record.cropType} - $quantity - $total',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (record.customerName.isNotEmpty)
                  Text(
                    record.customerName,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
        ],
      ),
    );
  }
}

class _ReceiveRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReceiveRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
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

class _ReceiverError extends StatelessWidget {
  final String message;

  const _ReceiverError({required this.message});

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

String _text(Map<String, dynamic> source, String key, [String fallback = '--']) {
  final value = source[key];
  final text = value == null ? '' : '$value'.trim();
  if (text.isEmpty || text == '--' || text.toLowerCase() == 'unknown') {
    return fallback;
  }
  return text;
}

double? _toDouble(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

String _scoreLabel(Map<String, dynamic> source) {
  final score = _text(source, 'score');
  if (score == '--') return score;
  return score.contains('/') ? score : '$score/100';
}

String _quantityLabel(Map<String, dynamic> source) {
  final quantity = _text(source, 'totalKg');
  if (quantity == '--') return quantity;
  final lower = quantity.toLowerCase();
  return lower.contains('kg') ? quantity : '$quantity kg';
}

String _bagLabel(Map<String, dynamic> source) {
  final bagCount = _text(source, 'bagCount');
  final bagSize = _text(source, 'bagSizeKg');
  if (bagCount == '--' && bagSize == '--') return '--';
  if (bagCount == '--') return '$bagSize kg bags';
  if (bagSize == '--') return bagCount;
  return '$bagCount bags x $bagSize kg';
}

String _percentLabel(Map<String, dynamic> source, String key) {
  final value = _text(source, key);
  if (value == '--') return value;
  return value.endsWith('%') ? value : '$value%';
}

String _dateTimeLabel(Map<String, dynamic> source) {
  final raw = _text(source, 'generatedAt', _text(source, 'verifiedAt'));
  if (raw == '--') return raw;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  final local = parsed.toLocal();
  return '${local.day}/${local.month}/${local.year} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
