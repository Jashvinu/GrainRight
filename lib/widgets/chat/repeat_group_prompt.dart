import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../config/theme.dart';
import '../../config/translations.dart';
import '../../controllers/form_controller.dart';
import '../../controllers/language_controller.dart';

class RepeatGroupPrompt extends StatefulWidget {
  final String groupKey;
  final String title;
  final String? cropRole;
  final FormController? formController;
  final void Function(List<Map<String, dynamic>> rows) onDone;

  const RepeatGroupPrompt({
    super.key,
    required this.groupKey,
    required this.title,
    this.cropRole,
    this.formController,
    required this.onDone,
  });

  @override
  State<RepeatGroupPrompt> createState() => _RepeatGroupPromptState();
}

class _RepeatGroupPromptState extends State<RepeatGroupPrompt> {
  final _kharifRows = <_KharifRow>[_KharifRow()];
  final _yearlyRows = <_YearlyRow>[
    _YearlyRow(2023),
    _YearlyRow(2024),
    _YearlyRow(2025),
  ];
  late final _PracticeRow _practiceRow;
  List<String> _cropOptions = const [];
  Map<String, String> _cropOptionLabels = const {};
  int _practiceStep = 0;
  static const _practiceStepCount = 4;

  @override
  void initState() {
    super.initState();
    _practiceRow = _PracticeRow(widget.cropRole ?? 'main');
    _prefillFromMainCrop();
  }

  /// Translates a UI string to Marathi when that language is active.
  String _tr(String text) {
    final lang = Get.find<LanguageController>();
    if (!lang.isMarathi) return text;
    return AppTranslations.translate(text);
  }

  void _prefillFromMainCrop() {
    final form = widget.formController;
    if (form == null) return;
    if (widget.groupKey != 'kharif_crops' && widget.groupKey != 'other_crops') {
      return;
    }
    final options = form.dropdownOptions['main_crop_v2'] ?? const <String>[];
    // "Other Crops" reuses the Kharif editor; the 'other' choice belongs only
    // under Kharif, so drop it from the crop-name dropdown for other crops.
    _cropOptions = widget.groupKey == 'other_crops'
        ? options.where((opt) => opt != 'other').toList()
        : options;
    _cropOptionLabels = {
      for (final opt in options) opt: form.localizedOptionLabel('main_crop_v2', opt),
    };
    final mainCrop = form.valueFor('main_crop')?.toString() ?? '';
    final mainArea = form.valueFor('main_crop_land_acre')?.toString() ?? '';
    if (mainCrop.isNotEmpty && options.contains(mainCrop)) {
      _kharifRows.first.cropNameValue = mainCrop;
      _kharifRows.first.cropName.text = _cropOptionLabels[mainCrop] ?? mainCrop;
    }
    if (mainArea.isNotEmpty) {
      _kharifRows.first.area.text = mainArea;
    }
  }

  @override
  void dispose() {
    for (final row in _kharifRows) {
      row.dispose();
    }
    for (final row in _yearlyRows) {
      row.dispose();
    }
    _practiceRow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPractice = widget.groupKey == 'crop_practices';
    final isLastStep = !isPractice || _practiceStep == _practiceStepCount - 1;
    final showBack = isPractice && _practiceStep > 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (isPractice) ...[
              const SizedBox(height: 6),
              Text(
                '${_tr('Step')} ${_practiceStep + 1} ${_tr('of')} $_practiceStepCount',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.greenDark,
                ),
              ),
            ],
            const SizedBox(height: 14),
            switch (widget.groupKey) {
              'kharif_crops' => _kharifEditor(),
              'other_crops' => _kharifEditor(),
              'main_crop_yearly' => _yearlyEditor(),
              'crop_practices' => _practiceStepBody(_practiceStep),
              _ => Text('Unsupported repeat group: ${widget.groupKey}'),
            },
            const SizedBox(height: 14),
            Row(
              children: [
                if (showBack) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          setState(() => _practiceStep -= 1),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: Text(_tr('Back')),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: showBack ? 1 : 2,
                  child: ElevatedButton(
                    onPressed: isLastStep
                        ? _submit
                        : () => setState(() => _practiceStep += 1),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(isLastStep ? _tr('Continue') : _tr('Next')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kharifEditor() {
    return Column(
      children: [
        for (var i = 0; i < _kharifRows.length; i++)
          _section('${_tr('Crop')} ${i + 1}', [
            _cropDropdown(_kharifRows[i]),
            if (_kharifRows[i].cropNameValue == 'other') ...[
              _text(_kharifRows[i].otherCropName, 'Other crop name'),
              _text(_kharifRows[i].otherCropDetails, 'Other crop details'),
            ],
            _text(
              _kharifRows[i].area,
              'Cultivated area (acre)',
              keyboardType: TextInputType.number,
            ),
            _text(_kharifRows[i].variety, 'Variety'),
            _text(
              _kharifRows[i].production,
              'Production quantity',
              keyboardType: TextInputType.number,
            ),
            _text(
              _kharifRows[i].cost,
              'Average estimated cost (Rupees ₹)',
              keyboardType: TextInputType.number,
            ),
          ]),
        if (_kharifRows.length < 4)
          TextButton.icon(
            onPressed: () => setState(() => _kharifRows.add(_KharifRow())),
            icon: const Icon(Icons.add, size: 24),
            label: Text(
              _tr('Add another crop'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }

  Widget _cropDropdown(_KharifRow row) {
    if (_cropOptions.isEmpty) {
      return _text(row.cropName, 'Crop name');
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: _cropOptions.contains(row.cropNameValue)
            ? row.cropNameValue
            : null,
        isExpanded: true,
        style: const TextStyle(fontSize: 18, color: Colors.black87),
        decoration: InputDecoration(
          labelText: _tr('Crop name'),
          labelStyle: const TextStyle(fontSize: 16),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final value in _cropOptions)
            DropdownMenuItem(
              value: value,
              child: Text(
                _cropOptionLabels[value] ?? value,
                style: const TextStyle(fontSize: 18),
              ),
            ),
        ],
        onChanged: (value) {
          if (value == null) return;
          setState(() {
            row.cropNameValue = value;
            row.cropName.text = _cropOptionLabels[value] ?? value;
          });
        },
      ),
    );
  }

  Widget _yearlyEditor() {
    return Column(
      children: [
        for (final row in _yearlyRows)
          _section(row.year.toString(), [
            _text(row.area, 'Area (acre)', keyboardType: TextInputType.number),
            _text(
              row.production,
              'Total production',
              keyboardType: TextInputType.number,
            ),
            _text(
              row.homeConsumption,
              'Home consumption',
              keyboardType: TextInputType.number,
            ),
            _text(
              row.quantitySold,
              'Quantity sold',
              keyboardType: TextInputType.number,
            ),
            _text(row.soldWhere, 'Sold where'),
            _text(
              row.sellingPrice,
              'Selling price (Rupees ₹)',
              keyboardType: TextInputType.number,
            ),
          ]),
      ],
    );
  }

  Widget _practiceStepBody(int step) {
    final row = _practiceRow;
    return switch (step) {
      0 => _section(_tr('Location and training'), [
        _singleChips(
          'Grown on',
          row.grownOnValue,
          const ['Own land', 'Forest patta', 'Leased land', 'Other'],
          (v) => setState(() {
            row.grownOnValue = v;
            row.grownOn.text = v;
          }),
        ),
        if (row.grownOnValue == 'Other')
          _text(row.grownOnOther, 'Other details'),
        _switch(
          'Same land every year?',
          row.sameLandEveryYear,
          (v) => setState(() => row.sameLandEveryYear = v),
        ),
        _singleChips(
          'Land topology',
          row.landTopologyValue,
          const ['Flat', 'Sloped', 'Terraced', 'Hilly', 'Other'],
          (v) => setState(() {
            row.landTopologyValue = v;
            row.landTopology.text = v;
          }),
        ),
        if (row.landTopologyValue == 'Other')
          _text(row.landTopologyOther, 'Other details'),
        _multiChips(
          'Seed sources',
          row.seedSourcesValues,
          const [
            'Own saved',
            'Local market',
            'Government source',
            'Neighbour',
            'Co-op society',
            'Other',
          ],
          (v) => setState(() {
            row.seedSourcesValues = v;
            row.seedSources.text = v.join(', ');
          }),
        ),
        if (row.seedSourcesValues.contains('Other'))
          _text(row.seedSourceOther, 'Other source details'),
        _switch(
          'Package of Practice training received?',
          row.popTrainingReceived,
          (v) => setState(() => row.popTrainingReceived = v),
        ),
        if (row.popTrainingReceived == true)
          _text(row.popTrainingSource, 'Training source'),
        _singleChips(
          'Farming method',
          row.farmingMethodValue,
          const ['Organic', 'Chemical', 'Mixed', 'Natural'],
          (v) => setState(() {
            row.farmingMethodValue = v;
            row.farmingMethod.text = v;
          }),
        ),
      ]),
      1 => _section(_tr('Seed and land preparation'), [
        _switch(
          'Treats seeds?',
          row.treatsSeeds,
          (v) => setState(() => row.treatsSeeds = v),
        ),
        if (row.treatsSeeds == true) ...[
          _multiChips(
            'Seed treatment materials',
            row.seedTreatmentMaterialsValues,
            const [
              'Cow dung',
              'Cow urine',
              'Neem',
              'Jeevamrut',
              'Chemical',
              'Other',
            ],
            (v) => setState(() {
              row.seedTreatmentMaterialsValues = v;
              row.seedTreatmentMaterials.text = v.join(', ');
            }),
          ),
          if (row.seedTreatmentMaterialsValues.contains('Other'))
            _text(row.seedTreatmentMaterialsOther, 'Other details'),
        ],
        _singleChips(
          'Seedling method',
          row.seedlingMethodValue,
          const ['Direct sowing', 'Nursery transplant', 'Broadcasting', 'Other'],
          (v) => setState(() {
            row.seedlingMethodValue = v;
            row.seedlingMethod.text = v;
          }),
        ),
        if (row.seedlingMethodValue == 'Other')
          _text(row.seedlingMethodOther, 'Other details'),
        _text(
          row.seedlingReadyDays,
          'Seedling ready (days)',
          keyboardType: TextInputType.number,
        ),
        _text(row.seedlingMethodDifference, 'Difference noticed'),
        _text(
          row.landPrepTractorDays,
          'Tractor days',
          keyboardType: TextInputType.number,
        ),
        _text(
          row.landPrepTractorCost,
          'Tractor cost (Rupees ₹)',
          keyboardType: TextInputType.number,
        ),
        _text(
          row.landPrepBullockDays,
          'Bullock days',
          keyboardType: TextInputType.number,
        ),
        _text(
          row.landPrepBullockCost,
          'Bullock cost (Rupees ₹)',
          keyboardType: TextInputType.number,
        ),
        _switch(
          'Land prepared by hand?',
          row.landPrepByHand,
          (v) => setState(() => row.landPrepByHand = v),
        ),
      ]),
      2 => _section(_tr('Transplanting and crop care'), [
        _singleChips(
          'Transplant method',
          row.transplantMethodValue,
          const ['By hand', 'Machine', 'Direct seed', 'Other'],
          (v) => setState(() {
            row.transplantMethodValue = v;
            row.transplantMethod.text = v;
          }),
        ),
        if (row.transplantMethodValue == 'Other')
          _text(row.transplantMethodOther, 'Other details'),
        _switch(
          'Dip in Jeevamrut?',
          row.dipInJeevamrut,
          (v) => setState(() => row.dipInJeevamrut = v),
        ),
        _text(
          row.plantSpacingCm,
          'Plant spacing (centimetres cm)',
          keyboardType: TextInputType.number,
        ),
        _text(
          row.transplantDays,
          'Transplant days',
          keyboardType: TextInputType.number,
        ),
        _switch(
          'Needs transplant labour?',
          row.needsTransplantLabour,
          (v) => setState(() => row.needsTransplantLabour = v),
        ),
        if (row.needsTransplantLabour == true) ...[
          _text(
            row.transplantLabourers,
            'How many labourers',
            keyboardType: TextInputType.number,
          ),
          _text(
            row.transplantDailyWage,
            'Daily wage (Rupees ₹)',
            keyboardType: TextInputType.number,
          ),
        ],
        _switch(
          'Does weeding?',
          row.doesWeeding,
          (v) => setState(() => row.doesWeeding = v),
        ),
        if (row.doesWeeding == true)
          _text(
            row.weedingAfterDays,
            'Weeding after (days)',
            keyboardType: TextInputType.number,
          ),
      ]),
      3 => _section(_tr('Pest, growth, harvest'), [
        _switch(
          'Sprays for pest?',
          row.spraysForPest,
          (v) => setState(() => row.spraysForPest = v),
        ),
        if (row.spraysForPest == true) ...[
          _multiChips(
            'Spray methods',
            row.sprayMethodsValues,
            const ['Neem', 'Matka', 'Jeevamrut', 'Pesticide', 'Other'],
            (v) => setState(() {
              row.sprayMethodsValues = v;
              row.sprayMethods.text = v.join(', ');
            }),
          ),
          if (row.sprayMethodsValues.contains('Matka'))
            _text(
              row.matkaPerAcre,
              'Matka per acre',
              keyboardType: TextInputType.number,
            ),
          if (row.sprayMethodsValues.contains('Neem'))
            _text(
              row.neemPerAcre,
              'Neem per acre',
              keyboardType: TextInputType.number,
            ),
          if (row.sprayMethodsValues.contains('Jeevamrut'))
            _text(
              row.jeevamrutPerAcre,
              'Jeevamrut per acre',
              keyboardType: TextInputType.number,
            ),
          if (row.sprayMethodsValues.contains('Pesticide'))
            _text(
              row.pesticidePerAcre,
              'Pesticide per acre',
              keyboardType: TextInputType.number,
            ),
          if (row.sprayMethodsValues.contains('Other'))
            _text(row.sprayMethodsOther, 'Other spray details'),
        ],
        _switch(
          'Does organic fertilizer help in disease control?',
          row.organicFertHelpsDisease,
          (v) => setState(() => row.organicFertHelpsDisease = v),
        ),
        _text(
          row.plantingToFloweringDays,
          'Planting to flowering (days)',
          keyboardType: TextInputType.number,
        ),
        _switch(
          'Uses fertilizer?',
          row.usesFertilizer,
          (v) => setState(() => row.usesFertilizer = v),
        ),
        if (row.usesFertilizer == true) ...[
          _text(row.fertilizerNames, 'Fertilizer names'),
          _text(
            row.fertilizerQtyPerAcre,
            'Quantity per acre',
            keyboardType: TextInputType.number,
          ),
        ],
        _switch(
          'Flowering pest problem?',
          row.floweringPestProblem,
          (v) => setState(() => row.floweringPestProblem = v),
        ),
        if (row.floweringPestProblem == true) ...[
          _text(row.floweringPestType, 'Pest type'),
          _text(row.floweringSpraysUsed, 'Sprays used'),
        ],
        _text(
          row.maturityDays,
          'Maturity (days)',
          keyboardType: TextInputType.number,
        ),
        _switch(
          'Monitors crop?',
          row.monitorsCrop,
          (v) => setState(() => row.monitorsCrop = v),
        ),
        if (row.monitorsCrop == true) ...[
          _multiChips(
            'Monitoring methods',
            row.monitoringMethodsValues,
            const ['Daily walk', 'Photos', 'Notes', 'Mobile app', 'Other'],
            (v) => setState(() {
              row.monitoringMethodsValues = v;
              row.monitoringMethods.text = v.join(', ');
            }),
          ),
          if (row.monitoringMethodsValues.contains('Other'))
            _text(row.monitoringMethodsOther, 'Other details'),
        ],
        _singleChips(
          'Harvest method',
          row.harvestMethodValue,
          const ['By hand', 'Machine', 'Mixed'],
          (v) => setState(() {
            row.harvestMethodValue = v;
            row.harvestMethod.text = v;
          }),
        ),
        _singleChips(
          'Harvest labour type',
          row.harvestLabourTypeValue,
          const ['Family', 'Hired', 'Mixed'],
          (v) => setState(() {
            row.harvestLabourTypeValue = v;
            row.harvestLabourType.text = v;
          }),
        ),
        _text(
          row.harvestDailyWage,
          'Harvest daily wage (Rupees ₹)',
          keyboardType: TextInputType.number,
        ),
        _text(
          row.harvestLabourers,
          'Harvest labourers',
          keyboardType: TextInputType.number,
        ),
        _text(
          row.harvestDays,
          'Harvest days',
          keyboardType: TextInputType.number,
        ),
        _text(
          row.readyToEatOrSellDays,
          'Ready to eat/sell (days)',
          keyboardType: TextInputType.number,
        ),
        _switch(
          'Sells this crop?',
          row.sellsMainCrop,
          (v) => setState(() => row.sellsMainCrop = v),
        ),
        if (row.sellsMainCrop == true)
          _singleChips(
            'When sold',
            row.sellingTimeValue,
            const [
              'Right after harvest',
              'Within 3 months',
              'Within 6 months',
              'Hold for better price',
            ],
            (v) => setState(() {
              row.sellingTimeValue = v;
              row.sellingTime.text = v;
            }),
          ),
      ]),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _text(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
  }) {
    final isNumeric =
        keyboardType == TextInputType.number ||
        keyboardType == TextInputType.phone;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 18),
        textCapitalization:
            isNumeric ? TextCapitalization.none : TextCapitalization.sentences,
        autocorrect: !isNumeric,
        enableSuggestions: !isNumeric,
        decoration: InputDecoration(
          labelText: _tr(label),
          labelStyle: const TextStyle(fontSize: 16),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 12,
          ),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _switch(String label, bool? value, ValueChanged<bool?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tr(label),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _bigToggleButton(
                  'Yes',
                  selected: value == true,
                  onTap: () => onChanged(true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _bigToggleButton(
                  'No',
                  selected: value == false,
                  onTap: () => onChanged(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _singleChips(
    String label,
    String? value,
    List<String> options,
    ValueChanged<String> onPick,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tr(label),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final option in options)
                _bigToggleButton(
                  option,
                  selected: value == option,
                  onTap: () => onPick(option),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _multiChips(
    String label,
    List<String> values,
    List<String> options,
    ValueChanged<List<String>> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tr(label),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final option in options)
                _bigToggleButton(
                  option,
                  selected: values.contains(option),
                  onTap: () {
                    final next = List<String>.from(values);
                    if (next.contains(option)) {
                      next.remove(option);
                    } else {
                      next.add(option);
                    }
                    onChanged(next);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bigToggleButton(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppTheme.green : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.green : Colors.grey.shade400,
            width: 1.5,
          ),
        ),
        child: Text(
          _tr(label),
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _submit() {
    final rows = switch (widget.groupKey) {
      'kharif_crops' =>
        _kharifRows
            .asMap()
            .entries
            .map((entry) => entry.value.toJson(entry.key + 1))
            .where((row) => row['crop_name'] != null)
            .toList(),
      'other_crops' =>
        _kharifRows
            .asMap()
            .entries
            .map((entry) => entry.value.toJson(entry.key + 1))
            .where((row) => row['crop_name'] != null)
            .toList(),
      'main_crop_yearly' => _yearlyRows.map((row) => row.toJson()).toList(),
      'crop_practices' => [_practiceRow.toJson()],
      _ => <Map<String, dynamic>>[],
    };
    widget.onDone(rows);
  }
}

class _KharifRow {
  final cropName = TextEditingController();
  final otherCropName = TextEditingController();
  final otherCropDetails = TextEditingController();
  final area = TextEditingController();
  final variety = TextEditingController();
  final production = TextEditingController();
  final cost = TextEditingController();
  String? cropNameValue;

  Map<String, dynamic> toJson(int position) => _compact({
    'position': position,
    'crop_name': cropNameValue ?? _textValue(cropName),
    'other_crop_name':
        cropNameValue == 'other' ? _textValue(otherCropName) : null,
    'other_crop_details':
        cropNameValue == 'other' ? _textValue(otherCropDetails) : null,
    'cultivated_area_acre': _doubleValue(area),
    'crop_variety': _textValue(variety),
    'production_qty': _doubleValue(production),
    'avg_estimated_cost': _doubleValue(cost),
  });

  void dispose() {
    cropName.dispose();
    otherCropName.dispose();
    otherCropDetails.dispose();
    area.dispose();
    variety.dispose();
    production.dispose();
    cost.dispose();
  }
}

class _YearlyRow {
  final int year;
  final area = TextEditingController();
  final production = TextEditingController();
  final homeConsumption = TextEditingController();
  final quantitySold = TextEditingController();
  final soldWhere = TextEditingController();
  final sellingPrice = TextEditingController();

  _YearlyRow(this.year);

  Map<String, dynamic> toJson() => _compact({
    'year': year,
    'area_acre': _doubleValue(area),
    'total_production': _doubleValue(production),
    'home_consumption': _doubleValue(homeConsumption),
    'quantity_sold': _doubleValue(quantitySold),
    'sold_where': _textValue(soldWhere),
    'selling_price': _doubleValue(sellingPrice),
  });

  void dispose() {
    area.dispose();
    production.dispose();
    homeConsumption.dispose();
    quantitySold.dispose();
    soldWhere.dispose();
    sellingPrice.dispose();
  }
}

class _PracticeRow {
  final String cropRole;
  final grownOn = TextEditingController();
  final grownOnOther = TextEditingController();
  final landTopology = TextEditingController();
  final landTopologyOther = TextEditingController();
  final seedSources = TextEditingController();
  final seedSourceOther = TextEditingController();
  final popTrainingSource = TextEditingController();
  final farmingMethod = TextEditingController();
  final seedTreatmentMaterials = TextEditingController();
  final seedTreatmentMaterialsOther = TextEditingController();
  final seedlingMethod = TextEditingController();
  final seedlingMethodOther = TextEditingController();
  final seedlingReadyDays = TextEditingController();
  final seedlingMethodDifference = TextEditingController();
  final landPrepTractorDays = TextEditingController();
  final landPrepTractorCost = TextEditingController();
  final landPrepBullockDays = TextEditingController();
  final landPrepBullockCost = TextEditingController();
  final transplantMethod = TextEditingController();
  final transplantMethodOther = TextEditingController();
  final plantSpacingCm = TextEditingController();
  final transplantDays = TextEditingController();
  final transplantLabourers = TextEditingController();
  final transplantDailyWage = TextEditingController();
  final weedingAfterDays = TextEditingController();
  final sprayMethods = TextEditingController();
  final matkaPerAcre = TextEditingController();
  final neemPerAcre = TextEditingController();
  final jeevamrutPerAcre = TextEditingController();
  final pesticidePerAcre = TextEditingController();
  final sprayMethodsOther = TextEditingController();
  final plantingToFloweringDays = TextEditingController();
  final fertilizerNames = TextEditingController();
  final fertilizerQtyPerAcre = TextEditingController();
  final floweringPestType = TextEditingController();
  final floweringSpraysUsed = TextEditingController();
  final maturityDays = TextEditingController();
  final monitoringMethods = TextEditingController();
  final monitoringMethodsOther = TextEditingController();
  final harvestMethod = TextEditingController();
  final harvestLabourType = TextEditingController();
  final harvestDailyWage = TextEditingController();
  final harvestLabourers = TextEditingController();
  final harvestDays = TextEditingController();
  final readyToEatOrSellDays = TextEditingController();
  final sellingTime = TextEditingController();

  bool? sameLandEveryYear;
  bool? popTrainingReceived;
  bool? treatsSeeds;
  bool? landPrepByHand;
  bool? dipInJeevamrut;
  bool? needsTransplantLabour;
  bool? doesWeeding;
  bool? spraysForPest;
  bool? organicFertHelpsDisease;
  bool? usesFertilizer;
  bool? floweringPestProblem;
  bool? monitorsCrop;
  bool? sellsMainCrop;

  String? grownOnValue;
  String? landTopologyValue;
  String? farmingMethodValue;
  String? seedlingMethodValue;
  String? transplantMethodValue;
  String? harvestMethodValue;
  String? harvestLabourTypeValue;
  String? sellingTimeValue;
  List<String> seedSourcesValues = [];
  List<String> seedTreatmentMaterialsValues = [];
  List<String> sprayMethodsValues = [];
  List<String> monitoringMethodsValues = [];

  _PracticeRow(this.cropRole);

  Map<String, dynamic> toJson() => _compact({
    'crop_role': cropRole,
    'grown_on': _textValue(grownOn),
    'grown_on_other': _textValue(grownOnOther),
    'same_land_every_year': sameLandEveryYear,
    'land_topology': _textValue(landTopology),
    'land_topology_other': _textValue(landTopologyOther),
    'seed_sources': _listValue(seedSources),
    'seed_source_other': _textValue(seedSourceOther),
    'pop_training_received': popTrainingReceived,
    'pop_training_source': _textValue(popTrainingSource),
    'farming_method': _textValue(farmingMethod),
    'treats_seeds': treatsSeeds,
    'seed_treatment_materials': _listValue(seedTreatmentMaterials),
    'seed_treatment_materials_other': _textValue(seedTreatmentMaterialsOther),
    'seedling_method': _textValue(seedlingMethod),
    'seedling_method_other': _textValue(seedlingMethodOther),
    'seedling_ready_days': _intValue(seedlingReadyDays),
    'seedling_method_difference': _textValue(seedlingMethodDifference),
    'land_prep_tractor_days': _doubleValue(landPrepTractorDays),
    'land_prep_tractor_cost': _doubleValue(landPrepTractorCost),
    'land_prep_bullock_days': _doubleValue(landPrepBullockDays),
    'land_prep_bullock_cost': _doubleValue(landPrepBullockCost),
    'land_prep_by_hand': landPrepByHand,
    'transplant_method': _textValue(transplantMethod),
    'transplant_method_other': _textValue(transplantMethodOther),
    'dip_in_jeevamrut': dipInJeevamrut,
    'plant_spacing_cm': _doubleValue(plantSpacingCm),
    'transplant_days': _intValue(transplantDays),
    'needs_transplant_labour': needsTransplantLabour,
    'transplant_labourers': _intValue(transplantLabourers),
    'transplant_daily_wage': _doubleValue(transplantDailyWage),
    'does_weeding': doesWeeding,
    'weeding_after_days': _intValue(weedingAfterDays),
    'sprays_for_pest': spraysForPest,
    'spray_methods': _listValue(sprayMethods),
    'matka_per_acre': _doubleValue(matkaPerAcre),
    'neem_per_acre': _doubleValue(neemPerAcre),
    'jeevamrut_per_acre': _doubleValue(jeevamrutPerAcre),
    'pesticide_per_acre': _doubleValue(pesticidePerAcre),
    'spray_methods_other': _textValue(sprayMethodsOther),
    'organic_fert_helps_disease': organicFertHelpsDisease,
    'planting_to_flowering_days': _intValue(plantingToFloweringDays),
    'uses_fertilizer': usesFertilizer,
    'fertilizer_names': _textValue(fertilizerNames),
    'fertilizer_qty_per_acre': _doubleValue(fertilizerQtyPerAcre),
    'flowering_pest_problem': floweringPestProblem,
    'flowering_pest_type': _textValue(floweringPestType),
    'flowering_sprays_used': _textValue(floweringSpraysUsed),
    'maturity_days': _intValue(maturityDays),
    'monitors_crop': monitorsCrop,
    'monitoring_methods': _listValue(monitoringMethods),
    'monitoring_methods_other': _textValue(monitoringMethodsOther),
    'harvest_method': _textValue(harvestMethod),
    'harvest_labour_type': _textValue(harvestLabourType),
    'harvest_daily_wage': _doubleValue(harvestDailyWage),
    'harvest_labourers': _intValue(harvestLabourers),
    'harvest_days': _intValue(harvestDays),
    'ready_to_eat_or_sell_days': _intValue(readyToEatOrSellDays),
    'sells_main_crop': sellsMainCrop,
    'selling_time': _textValue(sellingTime),
  });

  void dispose() {
    for (final controller in [
      grownOn,
      grownOnOther,
      landTopology,
      landTopologyOther,
      seedSources,
      seedSourceOther,
      popTrainingSource,
      farmingMethod,
      seedTreatmentMaterials,
      seedTreatmentMaterialsOther,
      seedlingMethod,
      seedlingMethodOther,
      seedlingReadyDays,
      seedlingMethodDifference,
      landPrepTractorDays,
      landPrepTractorCost,
      landPrepBullockDays,
      landPrepBullockCost,
      transplantMethod,
      transplantMethodOther,
      plantSpacingCm,
      transplantDays,
      transplantLabourers,
      transplantDailyWage,
      weedingAfterDays,
      sprayMethods,
      matkaPerAcre,
      neemPerAcre,
      jeevamrutPerAcre,
      pesticidePerAcre,
      sprayMethodsOther,
      plantingToFloweringDays,
      fertilizerNames,
      fertilizerQtyPerAcre,
      floweringPestType,
      floweringSpraysUsed,
      maturityDays,
      monitoringMethods,
      monitoringMethodsOther,
      harvestMethod,
      harvestLabourType,
      harvestDailyWage,
      harvestLabourers,
      harvestDays,
      readyToEatOrSellDays,
      sellingTime,
    ]) {
      controller.dispose();
    }
  }
}

String? _textValue(TextEditingController controller) {
  final text = controller.text.trim();
  return text.isEmpty ? null : text;
}

double? _doubleValue(TextEditingController controller) =>
    double.tryParse(controller.text.trim());

int? _intValue(TextEditingController controller) =>
    int.tryParse(controller.text.trim());

List<String>? _listValue(TextEditingController controller) {
  final values = controller.text
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
  return values.isEmpty ? null : values;
}

Map<String, dynamic> _compact(Map<String, dynamic> row) {
  row.removeWhere((_, value) => value == null);
  return row;
}
