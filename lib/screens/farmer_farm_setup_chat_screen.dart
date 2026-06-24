import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../config/ui_strings.dart';
import '../utils/boundary_map_launcher.dart';
import '../utils/polygon_geometry.dart';
import '../widgets/app_back_button.dart';

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

class _FarmerFarmSetupChatScreenState extends State<FarmerFarmSetupChatScreen> {
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
  final Set<String> _selectedIrrigationOptions = <String>{};
  final Set<String> _selectedHarvestIntentOptions = <String>{};

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
        return UiStrings.t('farm_setup_q_farm_name');
      case _SetupStep.markPolygon:
        return UiStrings.t('farm_setup_q_mark_polygon');
      case _SetupStep.crop:
        return UiStrings.t('farm_setup_q_crop');
      case _SetupStep.variety:
        return UiStrings.t('farm_setup_q_variety');
      case _SetupStep.previousCrop:
        return UiStrings.t('farm_setup_q_previous_crop');
      case _SetupStep.season:
        return UiStrings.t('farm_setup_q_season');
      case _SetupStep.irrigation:
        return UiStrings.t('farm_setup_q_irrigation');
      case _SetupStep.soilType:
        return UiStrings.t('farm_setup_q_soil');
      case _SetupStep.ownershipType:
        return UiStrings.t('farm_setup_q_ownership');
      case _SetupStep.seedSource:
        return UiStrings.t('farm_setup_q_seed_source');
      case _SetupStep.harvestIntent:
        return UiStrings.t('farm_setup_q_harvest_intent');
      case _SetupStep.sowingDate:
        return UiStrings.t('farm_setup_q_sowing_date');
      case _SetupStep.review:
        final date = _sowingDate == null
            ? '-'
            : '${_sowingDate!.day.toString().padLeft(2, '0')}/'
                  '${_sowingDate!.month.toString().padLeft(2, '0')}/'
                  '${_sowingDate!.year}';
        return '${UiStrings.t('review_and_continue')}:\n'
            '${UiStrings.t('farm_label')}: ${_displayValue(_farmName)}\n'
            '${UiStrings.t('land_marked_label')}: $_acresText\n'
            '${UiStrings.t('crop_label')}: ${_displayValue(_crop)}\n'
            '${UiStrings.t('variety_label')}: ${_displayValue(_variety)}\n'
            '${UiStrings.t('previous_crop_label')}: ${_displayValue(_previousCrop)}\n'
            '${UiStrings.t('season_label')}: ${_displayValue(_season)}\n'
            '${UiStrings.t('irrigation_label')}: ${_displayValue(_irrigation)}\n'
            '${UiStrings.t('soil_label')}: ${_displayValue(_soilType)}\n'
            '${UiStrings.t('ownership_label')}: ${_displayValue(_ownershipType)}\n'
            '${UiStrings.t('seed_source_label')}: ${_displayValue(_seedSource)}\n'
            '${UiStrings.t('harvest_use_label')}: ${_displayValue(_harvestIntent)}\n'
            '${UiStrings.t('sowing_date_label')}: $date';
    }
  }

  String _displayValue(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return '-';
    if (text.contains(',')) {
      return text
          .split(',')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .map(UiStrings.label)
          .join(', ');
    }
    return UiStrings.label(text);
  }

  bool get _isMultiSelectStep =>
      _step == _SetupStep.irrigation || _step == _SetupStep.harvestIntent;

  Set<String> get _activeMultiSelection => switch (_step) {
    _SetupStep.irrigation => _selectedIrrigationOptions,
    _SetupStep.harvestIntent => _selectedHarvestIntentOptions,
    _ => <String>{},
  };

  String get _acresText {
    final value = _computedAcres ?? 0;
    if (value <= 0) return UiStrings.t('zero_acres');
    return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${UiStrings.t('acres_unit')}';
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
        return const [
          'Rainfed',
          'Well',
          'Borewell',
          'Canal',
          'Drip',
          'Sprinkler',
          'Good water',
          'Limited water',
          'Water shortage',
        ];
      case _SetupStep.soilType:
        return const ['Black soil', 'Red soil', 'Sandy loam', 'Clay loam'];
      case _SetupStep.ownershipType:
        return const ['Owned', 'Leased', 'Shared', 'Forest patta'];
      case _SetupStep.seedSource:
        return const ['Own saved', 'FPO', 'Local market', 'Government source'];
      case _SetupStep.harvestIntent:
        return const [
          'Home use',
          'Market sale',
          'Seed saving',
          'Processing',
          'FPO sale',
          'Storage',
          'Fodder',
        ];
      case _SetupStep.sowingDate:
        return const ['Today', 'Yesterday', '3 days ago', '1 week ago'];
      case _SetupStep.review:
        return const [];
    }
  }

  String _suggestionLabel(String value) {
    final key = switch (value) {
      'North Field' => 'opt_north_field',
      'South Plot' => 'opt_south_plot',
      'East Block' => 'opt_east_block',
      'Main Farm' => 'opt_main_farm',
      'Mark polygon' => 'opt_mark_polygon',
      'Finger Millet' => 'opt_finger_millet',
      'Foxtail Millet' => 'opt_foxtail_millet',
      'Rice' => 'opt_rice',
      'Bajra' => 'opt_bajra',
      'Gira' => 'opt_gira',
      'Phule Nachni' => 'opt_phule_nachni',
      'Pragati' => 'pragati',
      'SiPS-1' => 'opt_sips_1',
      'BHU-8' => 'opt_bhu_8',
      'Kalyan' => 'opt_kalyan',
      'Indrayani' => 'opt_indrayani',
      'Basmati' => 'opt_basmati',
      'Kolum' => 'opt_kolum',
      'ICTP-8203' => 'opt_ictp_8203',
      'Shanti' => 'opt_shanti',
      'HHB-67' => 'opt_hhb_67',
      'Saburi' => 'opt_saburi',
      'Dhanshakti' => 'opt_dhanshakti',
      'Vegetables' => 'opt_vegetables',
      'Fallow' => 'opt_fallow',
      'Kharif' => 'opt_kharif',
      'Rabi' => 'opt_rabi',
      'Summer' => 'opt_summer',
      'Rainfed' => 'opt_rainfed',
      'Well' => 'opt_well',
      'Borewell' => 'opt_borewell',
      'Canal' => 'opt_canal',
      'Drip' => 'opt_drip',
      'Sprinkler' => 'opt_sprinkler',
      'Good water' => 'opt_good_water',
      'Limited water' => 'opt_limited_water',
      'Water shortage' => 'opt_water_shortage',
      'Black soil' => 'opt_black_soil',
      'Red soil' => 'opt_red_soil',
      'Sandy loam' => 'opt_sandy_loam',
      'Clay loam' => 'opt_clay_loam',
      'Owned' => 'opt_owned',
      'Leased' => 'opt_leased',
      'Shared' => 'opt_shared',
      'Forest patta' => 'opt_forest_patta',
      'Own saved' => 'opt_own_saved',
      'FPO' => 'opt_fpo',
      'Local market' => 'opt_local_market',
      'Government source' => 'opt_government_source',
      'Home use' => 'opt_home_use',
      'Market sale' => 'opt_market_sale',
      'Seed saving' => 'opt_seed_saving',
      'Processing' => 'opt_processing',
      'FPO sale' => 'opt_fpo_sale',
      'Storage' => 'storage',
      'Fodder' => 'opt_fodder',
      'Today' => 'opt_today',
      'Yesterday' => 'opt_yesterday',
      '3 days ago' => 'opt_three_days_ago',
      '1 week ago' => 'opt_one_week_ago',
      _ => '',
    };
    return key.isEmpty ? value : UiStrings.t(key);
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
      _appendMessage(UiStrings.t('boundary_not_captured'), isUser: false);
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
      UiStrings.t('farm_marked_area')
          .replaceAll('{points}', '${polygon.length}')
          .replaceAll('{area}', _acresText),
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

  void _appendUserText(String value, {String? displayText}) {
    _appendMessage(displayText ?? value, isUser: true);
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
          _appendMessage(UiStrings.t('date_parse_error'), isUser: false);
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
      _showToast(UiStrings.t('type_answer_first'));
      return;
    }
    _inputController.clear();
    _appendUserText(value);
  }

  void _toggleMultiSelectSuggestion(String suggestion) {
    final selection = _activeMultiSelection;
    setState(() {
      if (selection.contains(suggestion)) {
        selection.remove(suggestion);
      } else {
        selection.add(suggestion);
      }
    });
  }

  void _continueMultiSelectStep() {
    final selection = _activeMultiSelection;
    if (selection.isEmpty) {
      _showToast(UiStrings.t('select_one_option_first'));
      return;
    }
    final values = _quickSuggestionsForStep()
        .where(selection.contains)
        .toList(growable: false);
    final valueText = values.join(', ');
    final labelText = values.map(_suggestionLabel).join(', ');
    _appendUserText(valueText, displayText: labelText);
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
      _appendMessage(UiStrings.t('mark_boundary_first'), isUser: false);
      return;
    }
    if (_step == _SetupStep.crop && _crop == null) {
      _appendMessage(UiStrings.t('choose_crop_error'), isUser: false);
      return;
    }
    if (_step == _SetupStep.variety && _variety == null) {
      _appendMessage(UiStrings.t('choose_variety_error'), isUser: false);
      return;
    }
    if (_step == _SetupStep.sowingDate && _sowingDate == null) {
      _appendMessage(UiStrings.t('add_sowing_date_error'), isUser: false);
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
      _appendMessage(
        UiStrings.t('complete_all_fields_before_save'),
        isUser: false,
      );
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onQuickSelect(String suggestion) async {
    final label = _suggestionLabel(suggestion);
    if (_step == _SetupStep.markPolygon) {
      _appendMessage(label, isUser: true);
      await _openPolygonMap();
      return;
    }
    if (_step == _SetupStep.review) return;
    if (_isMultiSelectStep) {
      _toggleMultiSelectSuggestion(suggestion);
      return;
    }
    _appendUserText(suggestion, displayText: label);
  }

  @override
  Widget build(BuildContext context) {
    final quickSuggestions = _quickSuggestionsForStep();
    final reviewEnabled = _isFormComplete;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        title: Text(UiStrings.t('add_farm_title')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                itemCount: _messages.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
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
                        ? UiStrings.t('open_map_mark_land')
                        : '${UiStrings.t('remark_land')} ($_acresText)',
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
                        UiStrings.t('polygon_points_land')
                            .replaceAll('{points}', '${_polygon.length}')
                            .replaceAll('{area}', _acresText),
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: reviewEnabled ? _finishSetup : null,
                      child: Text(UiStrings.t('save_farm')),
                    ),
                  ],
                ),
              ),
            if (_step != _SetupStep.review)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: quickSuggestions
                          .map(
                            (item) => _isMultiSelectStep
                                ? FilterChip(
                                    label: Text(_suggestionLabel(item)),
                                    selected: _activeMultiSelection.contains(
                                      item,
                                    ),
                                    onSelected: (_) => _onQuickSelect(item),
                                  )
                                : ActionChip(
                                    label: Text(_suggestionLabel(item)),
                                    onPressed: () => _onQuickSelect(item),
                                  ),
                          )
                          .toList(),
                    ),
                    if (_isMultiSelectStep) ...[
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _activeMultiSelection.isEmpty
                            ? null
                            : _continueMultiSelectStep,
                        child: Text(UiStrings.t('continue_')),
                      ),
                    ],
                  ],
                ),
              ),
            if (_step != _SetupStep.markPolygon &&
                _step != _SetupStep.review &&
                !_isMultiSelectStep)
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
                        decoration: InputDecoration(
                          hintText: UiStrings.t('type_answer_hint'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: UiStrings.t('send'),
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
