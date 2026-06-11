import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../config/theme.dart';
import '../utils/boundary_map_launcher.dart';
import '../utils/polygon_geometry.dart';

class FarmSetupChatResult {
  final String farmName;
  final String crop;
  final String variety;
  final String acres;
  final double computedAcres;
  final String previousCrop;
  final String season;
  final String irrigation;
  final String soilType;
  final String ownershipType;
  final String seedSource;
  final String harvestIntent;
  final DateTime sowingDate;
  final List<List<double>> polygon;

  const FarmSetupChatResult({
    required this.farmName,
    required this.crop,
    required this.variety,
    required this.acres,
    required this.computedAcres,
    required this.previousCrop,
    required this.season,
    required this.irrigation,
    required this.soilType,
    required this.ownershipType,
    required this.seedSource,
    required this.harvestIntent,
    required this.sowingDate,
    required this.polygon,
  });
}

enum _SetupStep {
  farmName,
  markPolygon,
  crop,
  variety,
  previousCrop,
  season,
  irrigation,
  soilType,
  ownershipType,
  seedSource,
  harvestIntent,
  sowingDate,
  review,
}

class FarmerFarmSetupChatScreen extends StatefulWidget {
  const FarmerFarmSetupChatScreen({super.key});

  @override
  State<FarmerFarmSetupChatScreen> createState() =>
      _FarmerFarmSetupChatScreenState();
}

class _FarmerFarmSetupChatScreenState
    extends State<FarmerFarmSetupChatScreen> {
  static const Map<String, List<String>> _cropVarieties = {
    'Finger Millet': ['Gira', 'Phule Nachni'],
    'Foxtail Millet': ['Pragati', 'SiPS-1', 'BHU-8', 'Kalyan'],
    'Rice': ['Indrayani', 'Basmati', 'Kolum'],
    'Bajra': ['ICTP-8203', 'Shanti', 'HHB-67', 'Saburi', 'Dhanshakti'],
  };

  static const List<String> _cropTypes = [
    'Finger Millet',
    'Foxtail Millet',
    'Rice',
    'Bajra',
  ];

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_SetupMessage> _messages = [];
  final List<List<double>> _polygon = [];

  _SetupStep _step = _SetupStep.farmName;
  String? _farmName;
  String? _crop;
  String? _variety;
  String? _previousCrop;
  String? _season;
  String? _irrigation;
  String? _soilType;
  String? _ownershipType;
  String? _seedSource;
  String? _harvestIntent;
  DateTime? _sowingDate;
  double? _computedAcres;

  @override
  void initState() {
    super.initState();
    _appendMessage(_questionMessageForStep(_step), isUser: false);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _questionMessageForStep(_SetupStep step) {
    switch (step) {
      case _SetupStep.farmName:
        return 'First, tell me your farm name.';
      case _SetupStep.markPolygon:
        return 'Mark the farm boundary on the map. I will calculate land area in acres automatically.';
      case _SetupStep.crop:
        return 'Choose the crop grown on this farm.';
      case _SetupStep.variety:
        return 'Choose the crop variety.';
      case _SetupStep.previousCrop:
        return 'Which crop was sown here previously?';
      case _SetupStep.season:
        return 'Which season is this crop for?';
      case _SetupStep.irrigation:
        return 'What is the irrigation source or water condition?';
      case _SetupStep.soilType:
        return 'What is the soil type?';
      case _SetupStep.ownershipType:
        return 'What is the land ownership type?';
      case _SetupStep.seedSource:
        return 'Where did the seed come from?';
      case _SetupStep.harvestIntent:
        return 'What is the main harvest use?';
      case _SetupStep.sowingDate:
        return 'When did you sow? Select from menu or type yyyy-mm-dd.';
      case _SetupStep.review:
        final date = _sowingDate == null
            ? '-'
            : '${_sowingDate!.day.toString().padLeft(2, '0')}/'
                '${_sowingDate!.month.toString().padLeft(2, '0')}/'
                '${_sowingDate!.year}';
        return 'Review and continue:\n'
            'Farm: ${_farmName ?? '-'}\n'
            'Land marked: ${_acresText}\n'
            'Crop: ${_crop ?? '-'}\n'
            'Variety: ${_variety ?? '-'}\n'
            'Previous crop: ${_previousCrop ?? '-'}\n'
            'Season: ${_season ?? '-'}\n'
            'Irrigation: ${_irrigation ?? '-'}\n'
            'Soil: ${_soilType ?? '-'}\n'
            'Ownership: ${_ownershipType ?? '-'}\n'
            'Seed source: ${_seedSource ?? '-'}\n'
            'Harvest use: ${_harvestIntent ?? '-'}\n'
            'Sowing date: $date';
    }
  }

  String get _acresText {
    final value = _computedAcres ?? 0;
    if (value <= 0) return '0 acres';
    return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} acres';
  }

  List<String> _quickSuggestionsForStep() {
    switch (_step) {
      case _SetupStep.farmName:
        return const ['North Field', 'South Plot', 'East Block', 'Main Farm'];
      case _SetupStep.markPolygon:
        return const ['Mark polygon'];
      case _SetupStep.crop:
        return _cropTypes;
      case _SetupStep.variety:
        final crop = _crop;
        return crop == null ? const [] : _cropVarieties[crop] ?? const [];
      case _SetupStep.previousCrop:
        return const ['Finger Millet', 'Rice', 'Bajra', 'Vegetables', 'Fallow'];
      case _SetupStep.season:
        return const ['Kharif', 'Rabi', 'Summer'];
      case _SetupStep.irrigation:
        return const ['Rainfed', 'Well', 'Borewell', 'Canal', 'Drip'];
      case _SetupStep.soilType:
        return const ['Black soil', 'Red soil', 'Sandy loam', 'Clay loam'];
      case _SetupStep.ownershipType:
        return const ['Owned', 'Leased', 'Shared', 'Forest patta'];
      case _SetupStep.seedSource:
        return const ['Own saved', 'FPO', 'Local market', 'Government source'];
      case _SetupStep.harvestIntent:
        return const ['Home use', 'Market sale', 'Seed saving', 'Processing'];
      case _SetupStep.sowingDate:
        return const ['Today', 'Yesterday', '3 days ago', '1 week ago'];
      case _SetupStep.review:
        return const [];
    }
  }

  bool get _isFormComplete {
    return _farmName != null &&
        _polygon.isNotEmpty &&
        (_computedAcres ?? 0) > 0 &&
        _crop != null &&
        _variety != null &&
        _previousCrop != null &&
        _season != null &&
        _irrigation != null &&
        _soilType != null &&
        _ownershipType != null &&
        _seedSource != null &&
        _harvestIntent != null &&
        _sowingDate != null;
  }

  Future<void> _openPolygonMap() async {
    final polygon = await openBoundaryDrawingMap(initialPolygon: _polygon);
    if (polygon == null || polygon.length < 3) {
      _appendMessage(
        'Boundary not captured. Mark at least 3 points on the map.',
        isUser: false,
      );
      return;
    }

    final ring = PolygonGeometry.fromGeoJsonRing(polygon);
    final hectares = PolygonGeometry.areaHectares(ring);
    final acres = hectares * 2.47105;
    _polygon
      ..clear()
      ..addAll(polygon);
    _computedAcres = acres;
    _appendMessage(
      'Farm marked with ${polygon.length} points. Land area fetched as ${_acresText}.',
      isUser: false,
    );
    _advanceStep();
  }

  void _appendMessage(String text, {required bool isUser}) {
    setState(() {
      _messages.add(_SetupMessage(isUser: isUser, text: text));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _appendUserText(String value) {
    _appendMessage(value, isUser: true);
    switch (_step) {
      case _SetupStep.farmName:
        _farmName = value;
        break;
      case _SetupStep.crop:
        _crop = value;
        _variety = null;
        break;
      case _SetupStep.variety:
        _variety = value;
        break;
      case _SetupStep.previousCrop:
        _previousCrop = value;
        break;
      case _SetupStep.season:
        _season = value;
        break;
      case _SetupStep.irrigation:
        _irrigation = value;
        break;
      case _SetupStep.soilType:
        _soilType = value;
        break;
      case _SetupStep.ownershipType:
        _ownershipType = value;
        break;
      case _SetupStep.seedSource:
        _seedSource = value;
        break;
      case _SetupStep.harvestIntent:
        _harvestIntent = value;
        break;
      case _SetupStep.sowingDate:
        final parsed = _parseSowingDate(value);
        if (parsed == null) {
          _appendMessage('I could not parse this date. Use yyyy-mm-dd.', isUser: false);
          return;
        }
        _sowingDate = parsed;
        break;
      case _SetupStep.markPolygon:
      case _SetupStep.review:
        break;
    }
    _advanceStep();
  }

  Future<void> _onSend() async {
    final value = _inputController.text.trim();
    if (value.isEmpty) {
      _showToast('Type an answer first');
      return;
    }
    _inputController.clear();
    _appendUserText(value);
  }

  DateTime? _parseSowingDate(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'today') return DateTime.now();
    if (normalized == 'yesterday') {
      return DateTime.now().subtract(const Duration(days: 1));
    }
    if (normalized == '3 days ago') {
      return DateTime.now().subtract(const Duration(days: 3));
    }
    if (normalized == '1 week ago' || normalized == 'last week') {
      return DateTime.now().subtract(const Duration(days: 7));
    }
    final direct = DateTime.tryParse(value);
    if (direct != null) return direct;
    final parts = value.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    return null;
  }

  void _advanceStep() {
    if (_step == _SetupStep.review) return;
    if (_step == _SetupStep.markPolygon &&
        (_polygon.isEmpty || (_computedAcres ?? 0) <= 0)) {
      _appendMessage('Mark the farm boundary first.', isUser: false);
      return;
    }
    if (_step == _SetupStep.crop && _crop == null) {
      _appendMessage('Choose a crop.', isUser: false);
      return;
    }
    if (_step == _SetupStep.variety && _variety == null) {
      _appendMessage('Choose a variety.', isUser: false);
      return;
    }
    if (_step == _SetupStep.sowingDate && _sowingDate == null) {
      _appendMessage('Add sowing date.', isUser: false);
      return;
    }

    final next = switch (_step) {
      _SetupStep.farmName => _SetupStep.markPolygon,
      _SetupStep.markPolygon => _SetupStep.crop,
      _SetupStep.crop => _SetupStep.variety,
      _SetupStep.variety => _SetupStep.previousCrop,
      _SetupStep.previousCrop => _SetupStep.season,
      _SetupStep.season => _SetupStep.irrigation,
      _SetupStep.irrigation => _SetupStep.soilType,
      _SetupStep.soilType => _SetupStep.ownershipType,
      _SetupStep.ownershipType => _SetupStep.seedSource,
      _SetupStep.seedSource => _SetupStep.harvestIntent,
      _SetupStep.harvestIntent => _SetupStep.sowingDate,
      _SetupStep.sowingDate => _SetupStep.review,
      _SetupStep.review => _SetupStep.review,
    };

    setState(() => _step = next);
    _appendMessage(_questionMessageForStep(_step), isUser: false);
  }

  void _finishSetup() {
    if (!_isFormComplete) {
      _appendMessage('Please complete all fields before saving.', isUser: false);
      return;
    }
    Navigator.pop(
      context,
      FarmSetupChatResult(
        farmName: _farmName!.trim(),
        crop: _crop!.trim(),
        variety: _variety!.trim(),
        acres: (_computedAcres ?? 0).toStringAsFixed(2),
        computedAcres: _computedAcres ?? 0,
        previousCrop: _previousCrop!.trim(),
        season: _season!.trim(),
        irrigation: _irrigation!.trim(),
        soilType: _soilType!.trim(),
        ownershipType: _ownershipType!.trim(),
        seedSource: _seedSource!.trim(),
        harvestIntent: _harvestIntent!.trim(),
        sowingDate: _sowingDate!,
        polygon: List<List<double>>.from(_polygon),
      ),
    );
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onQuickSelect(String suggestion) async {
    if (_step == _SetupStep.markPolygon) {
      _appendMessage(suggestion, isUser: true);
      await _openPolygonMap();
      return;
    }
    if (_step == _SetupStep.review) return;
    _appendUserText(suggestion);
  }

  @override
  Widget build(BuildContext context) {
    final quickSuggestions = _quickSuggestionsForStep();
    final reviewEnabled = _isFormComplete;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Add farm')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                itemCount: _messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = _messages[index];
                  return Align(
                    alignment: item.isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 340),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: item.isUser ? AppTheme.greenPale : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: item.isUser
                              ? const Color(0xFFB7D6BE)
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: Text(
                        item.text,
                        style: const TextStyle(
                          color: AppTheme.textDark,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_step == _SetupStep.markPolygon)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: OutlinedButton.icon(
                  onPressed: _openPolygonMap,
                  icon: const Icon(Icons.edit_location_alt_rounded),
                  label: Text(
                    _computedAcres == null
                        ? 'Open map and mark land'
                        : 'Re-mark land ($_acresText)',
                  ),
                ),
              ),
            if (_step == _SetupStep.review)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_polygon.isNotEmpty)
                      Text(
                        'Polygon points: ${_polygon.length} • Land marked: $_acresText',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: reviewEnabled ? _finishSetup : null,
                      child: const Text('Save farm'),
                    ),
                  ],
                ),
              ),
            if (_step != _SetupStep.review)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: quickSuggestions
                      .map(
                        (item) => ActionChip(
                          label: Text(item),
                          onPressed: () => _onQuickSelect(item),
                        ),
                      )
                      .toList(),
                ),
              ),
            if (_step != _SetupStep.markPolygon && _step != _SetupStep.review)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _onSend(),
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Type your answer...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Send',
                      onPressed: _onSend,
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            if (_step != _SetupStep.review) const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

class _SetupMessage {
  final bool isUser;
  final String text;

  const _SetupMessage({required this.isUser, required this.text});
}
