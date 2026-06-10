import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../config/theme.dart';
import '../utils/boundary_map_launcher.dart';

class FarmSetupChatResult {
  final String farmName;
  final String crop;
  final String variety;
  final String acres;
  final DateTime sowingDate;
  final List<List<double>> polygon;

  const FarmSetupChatResult({
    required this.farmName,
    required this.crop,
    required this.variety,
    required this.acres,
    required this.sowingDate,
    required this.polygon,
  });
}

enum _SetupStep {
  farmName,
  markPolygon,
  crop,
  variety,
  acres,
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
    'Finger Millet': ['Brown Top', 'Ravi', 'Sita', 'PRH-10'],
    'Foxtail Millet': ['Pragati', 'SiPS-1', 'BHU-8', 'Kalyan'],
    'Rice': ['Basmati', 'Karnal Local', 'IR-64', 'Hybrid'],
    'Bajra': ['HHB 67', 'HHB 208', 'Rajani', 'RNB-71'],
  };

  static const List<String> _cropTypes = [
    'Finger Millet',
    'Foxtail Millet',
    'Rice',
    'Bajra',
  ];

  static const List<String> _quickAcres = [
    '1',
    '2',
    '3',
    '5',
  ];

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_SetupMessage> _messages = [];

  final List<List<double>> _polygon = [];

  _SetupStep _step = _SetupStep.farmName;
  String? _farmName;
  String? _crop;
  String? _variety;
  String? _acres;
  DateTime? _sowingDate;

  @override
  void initState() {
    super.initState();
    _pushBotIntro();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _pushBotIntro() {
    _appendMessage(
      _questionMessageForStep(_step),
      isUser: false,
    );
  }

  String _questionMessageForStep(_SetupStep step) {
    switch (step) {
      case _SetupStep.farmName:
        return 'First, tell me your farm name.';
      case _SetupStep.markPolygon:
        return 'Now mark the farm polygon on the map.';
      case _SetupStep.crop:
        return 'Choose crop grown on this farm.';
      case _SetupStep.variety:
        return 'Choose variety for this crop.';
      case _SetupStep.acres:
        return 'How many acres of land is this farm?';
      case _SetupStep.sowingDate:
        return 'When did you sow? Select from menu or type (yyyy-mm-dd).';
      case _SetupStep.review:
        final name = _farmName ?? '-';
        final crop = _crop ?? '-';
        final variety = _variety ?? '-';
        final acres = _acres ?? '-';
        final date = _sowingDate == null
            ? '-'
            : '${_sowingDate!.day.toString().padLeft(2, '0')}'
                '/${_sowingDate!.month.toString().padLeft(2, '0')}'
                '/${_sowingDate!.year}';
        return 'Review and continue:\n'
            'Farm: $name\n'
            'Crop: $crop\n'
            'Variety: $variety\n'
            'Acres: $acres\n'
            'Sowing date: $date';
    }
  }

  List<String> _quickSuggestionsForStep() {
    switch (_step) {
      case _SetupStep.farmName:
        return const [
          'North Field',
          'South Plot',
          'East Block',
          'Main Farm',
        ];
      case _SetupStep.markPolygon:
        return const ['Mark polygon'];
      case _SetupStep.crop:
        return _cropTypes;
      case _SetupStep.variety:
        final crop = _crop;
        if (crop != null && _cropVarieties.containsKey(crop)) {
          return _cropVarieties[crop]!;
        }
        return const ['Brown Top', 'Pragati', 'Hybrid'];
      case _SetupStep.acres:
        return _quickAcres;
      case _SetupStep.sowingDate:
        return const ['Today', 'Yesterday', '3 days ago', '1 week ago'];
      case _SetupStep.review:
        return const [];
    }
  }

  bool get _isFormComplete {
    return _farmName != null &&
        _crop != null &&
        _variety != null &&
        _acres != null &&
        _sowingDate != null;
  }

  Future<void> _openPolygonMap() async {
    final polygon = await openBoundaryDrawingMap();
    if (polygon == null) {
      _appendMessage(
        'Polygon not captured. Tap again when you are ready.',
        isUser: false,
      );
      return;
    }
    _polygon
      ..clear()
      ..addAll(polygon);
    _appendMessage(
      'Polygon captured with ${polygon.length} points.',
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
      case _SetupStep.acres:
        _acres = value;
        break;
      case _SetupStep.sowingDate:
        final parsed = _parseSowingDate(value);
        if (parsed == null) {
          _appendMessage(
            'I could not parse this date. Use format yyyy-mm-dd.',
            isUser: false,
          );
          return;
        }
        _sowingDate = parsed;
        break;
      default:
        break;
    }
    if (_step == _SetupStep.sowingDate && _sowingDate == null) {
      return;
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
    if (normalized == 'today') {
      return DateTime.now();
    }
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
    if (_step == _SetupStep.markPolygon && _polygon.isEmpty) {
      _appendMessage('Mark polygon first to continue.', isUser: false);
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
    if (_step == _SetupStep.acres && (_acres == null || _acres!.trim().isEmpty)) {
      _appendMessage('Add acres value.', isUser: false);
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
      _SetupStep.variety => _SetupStep.acres,
      _SetupStep.acres => _SetupStep.sowingDate,
      _SetupStep.sowingDate => _SetupStep.review,
      _SetupStep.review => _SetupStep.review,
    };

    setState(() => _step = next);
    if (_step != _SetupStep.review) {
      _appendMessage(_questionMessageForStep(_step), isUser: false);
    }
  }

  void _finishSetup() {
    if (!_isFormComplete) {
      _appendMessage('Please complete all fields before saving.', isUser: false);
      return;
    }
    final polygon = List<List<double>>.from(_polygon);
    Navigator.pop(
      context,
      FarmSetupChatResult(
        farmName: _farmName!.trim(),
        crop: _crop!.trim(),
        variety: _variety!.trim(),
        acres: _acres!.trim(),
        sowingDate: _sowingDate!,
        polygon: polygon,
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
      if (suggestion == 'Mark polygon') {
        await _openPolygonMap();
      }
      return;
    }
    if (_step == _SetupStep.sowingDate) {
      _appendUserText(suggestion);
      return;
    }
    if (_step == _SetupStep.review) {
      return;
    }
    _appendUserText(suggestion);
  }

  @override
  Widget build(BuildContext context) {
    final quickSuggestions = _quickSuggestionsForStep();
    final reviewEnabled = _isFormComplete;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Add farm'),
      ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: item.isUser
                            ? AppTheme.greenPale
                            : Colors.white,
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
                padding:
                    const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: OutlinedButton.icon(
                  onPressed: _openPolygonMap,
                  icon: const Icon(Icons.edit_location_alt_rounded),
                  label: const Text('Open map and mark polygon'),
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
                        'Polygon points: ${_polygon.length} ',
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
            if (_step != _SetupStep.review)
              const SizedBox(height: 14),
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
