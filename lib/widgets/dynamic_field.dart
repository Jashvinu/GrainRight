import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:kalsubai_farms/core/localization/locale_text.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import '../controllers/form_controller.dart';
import '../controllers/language_controller.dart';
import '../models/form_config.dart';
import '../utils/boundary_map_launcher.dart';
import 'acre_input.dart';
import 'custom_dropdown.dart';
import 'custom_text_field.dart';
import 'yes_no_toggle.dart';
import 'polygon_map_field.dart';
import 'multi_select_chip_field.dart';
import 'millet_land_picker_field.dart';

class DynamicField extends StatelessWidget {
  final FormFieldConfig config;

  const DynamicField({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<FormController>();
    if (config.visibilityRule != null) {
      return Obx(() {
        if (!c.isFieldVisible(config)) return const SizedBox.shrink();
        return _buildField(context, c);
      });
    }
    return _buildField(context, c);
  }

  String _trLabel(String label) => UiStrings.fromEnglish(label);

  String _label(BuildContext context) => config.localizedLabel(context);

  Widget _buildField(BuildContext context, FormController c) {
    return Obx(() {
      // Subscribe to language changes so field rebuilds on toggle
      final _ = Get.find<LanguageController>().language.value;

      if (config.inputType == 'dropdown' && config.fieldKey == 'disease_name') {
        return _buildDropdownWithOther(
          context,
          c,
          otherKey: 'disease_name_other',
          otherLabel: 'Other disease name',
        );
      }
      if (config.inputType == 'dropdown' &&
          config.fieldKey == 'affected_crop') {
        return _buildAffectedCropDropdown(context, c);
      }

      return switch (config.inputType) {
        'text' => CustomTextField(
          label: _translatedLabel(context),
          controller: c.textController(config.fieldKey),
          hintText: _localizedHint(context),
          suffixText: _localizedSuffix(),
          validator: _buildValidator(),
        ),
        'textarea' => CustomTextField(
          label: _translatedLabel(context),
          controller: c.textController(config.fieldKey),
          hintText: _localizedHint(context),
          suffixText: _localizedSuffix(),
          maxLines: 4,
          validator: _buildValidator(),
        ),
        'numeric' => CustomTextField(
          label: _translatedLabel(context),
          controller: c.textController(config.fieldKey),
          numeric: true,
          hintText: _localizedHint(context),
          suffixText: _localizedSuffix(),
          validator: _buildValidator(),
        ),
        'currency' => _buildCurrencyField(context, c),
        'acre' => AcreInput(
          label: _label(context),
          controller: c.textController(config.fieldKey),
        ),
        'boolean' => YesNoToggle(
          label: _label(context),
          value: c.boolValue(config.fieldKey),
        ),
        'dropdown' => _buildDropdown(context, c),
        'date' => _buildDatePicker(context, c),
        'mobile' => _buildMobileField(context, c),
        'aadhar' => _buildAadharField(context, c),
        'polygon' => PolygonMapField(
          label: _label(context),
          hasError:
              config.isRequired &&
              c.polygonValue(config.fieldKey).value == null,
          polygonState: c.polygonValue(config.fieldKey),
        ),
        'polygon_pencil' => _buildPencilPolygonField(c),
        'auto_calc' => _buildAutoCalcDisplay(context, c),
        'multiselect' => MultiSelectChipField(
          label: _translatedLabel(context),
          options: c.dropdownOptions[config.dropdownOptionsKey] ?? [],
          selected: c.multiSelectValue(config.fieldKey),
          optionKey: config.dropdownOptionsKey,
        ),
        'millet_land_picker' => MilletLandPickerField(label: _label(context)),
        _ => const SizedBox.shrink(),
      };
    });
  }

  Widget _buildPencilPolygonField(FormController c) {
    final state = c.polygonValue(config.fieldKey);
    return Obx(() {
      final points = state.value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: OutlinedButton.icon(
          onPressed: () async {
            final result = await openBoundaryDrawingMap(initialPolygon: points);
            if (result != null) {
              c.setPolygon(config.fieldKey, result);
            }
          },
          icon: const Icon(Icons.edit_location_alt_rounded),
          label: Text(
            points == null || points.isEmpty
                ? _trLabel('Draw your farm boundary')
                : _trLabel('Farm boundary saved'),
          ),
        ),
      );
    });
  }

  String _translatedLabel(BuildContext context) {
    final label = UiStrings.fromEnglish(_label(context));
    return config.isRequired ? '$label *' : label;
  }

  String? _localizedHint(BuildContext context) {
    final hint = config.localizedHint(context);
    return hint == null ? null : UiStrings.fromEnglish(hint);
  }

  String? _localizedSuffix() {
    final suffix = config.suffixText;
    return suffix == null ? null : UiStrings.fromEnglish(suffix);
  }

  Widget _buildCurrencyField(BuildContext context, FormController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c.textController(config.fieldKey),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        decoration: InputDecoration(
          labelText: _translatedLabel(context),
          prefixText: '${UiStrings.t('currency_rs')}  ',
          suffixText: _localizedSuffix(),
          suffixStyle: TextStyle(
            color: Colors.grey[500],
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        validator: _buildValidator(),
      ),
    );
  }

  Widget _buildDropdown(BuildContext context, FormController c) {
    final items = c.dropdownOptions[config.dropdownOptionsKey] ?? [];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: InputDecorator(
          decoration: InputDecoration(labelText: _label(context)),
          child: Text(
            _trLabel('No options'),
            style: TextStyle(color: Colors.grey[400]),
          ),
        ),
      );
    }
    return CustomDropdown(
      label: _label(context),
      items: items,
      selected: c.dropdownValue(config.fieldKey),
      optionKey: config.dropdownOptionsKey,
    );
  }

  Widget _buildDropdownWithOther(
    BuildContext context,
    FormController c, {
    required String otherKey,
    required String otherLabel,
  }) {
    final items = c.dropdownOptions[config.dropdownOptionsKey] ?? [];
    final selected = c.dropdownValue(config.fieldKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStandardDropdown(
          label: _label(context),
          items: items,
          selectedValue: selected.value,
          itemLabel: (value) =>
              c.localizedOptionLabel(config.dropdownOptionsKey, value),
          onChanged: (value) {
            c.setDropdown(config.fieldKey, value);
            if (value != 'Other') c.clearAuxText(otherKey);
          },
        ),
        if (selected.value == 'Other')
          CustomTextField(
            label: _trLabel(otherLabel),
            controller: c.auxTextController(otherKey),
            hintText: _trLabel('Write name if not listed'),
          ),
      ],
    );
  }

  Widget _buildAffectedCropDropdown(BuildContext context, FormController c) {
    final selected = c.dropdownValue(config.fieldKey);
    final items = c.affectedCropOptions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStandardDropdown(
          label: _label(context),
          items: items,
          selectedValue: items.contains(selected.value) ? selected.value : null,
          itemLabel: c.affectedCropLabel,
          onChanged: (value) {
            c.setDropdown(config.fieldKey, value);
            if (value != 'Other') c.clearAuxText('affected_crop_other');
          },
        ),
        if (selected.value == 'Other')
          CustomTextField(
            label: _trLabel('Other crop affected'),
            controller: c.auxTextController('affected_crop_other'),
            hintText: _trLabel('Write crop name if not listed'),
          ),
      ],
    );
  }

  Widget _buildStandardDropdown({
    required String label,
    required List<String> items,
    required String? selectedValue,
    required String Function(String value) itemLabel,
    required ValueChanged<String?> onChanged,
  }) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Text(
            _trLabel('No options'),
            style: TextStyle(color: Colors.grey[400]),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-${selectedValue ?? ''}-${items.join('|')}'),
        initialValue: selectedValue,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final value in items)
            DropdownMenuItem(value: value, child: Text(itemLabel(value))),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildDatePicker(BuildContext context, FormController c) {
    final rxDate = c.dateValue(config.fieldKey);
    // Default range starts in 1930 so date-of-birth years are selectable;
    // a `date_min` validation rule can still narrow it per field.
    DateTime firstDate = DateTime(1930);
    DateTime lastDate = DateTime.now();

    final validation = config.validation;
    if (validation.containsKey('date_min')) {
      final minStr = validation['date_min'] as String;
      firstDate = DateTime.tryParse(minStr) ?? firstDate;
    }
    if (validation.containsKey('date_max')) {
      final maxStr = validation['date_max'] as String;
      if (maxStr == 'today') {
        lastDate = DateTime.now();
      } else {
        lastDate = DateTime.tryParse(maxStr) ?? lastDate;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Obx(
        () => InkWell(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate:
                  rxDate.value ??
                  (lastDate.isBefore(DateTime.now())
                      ? lastDate
                      : DateTime.now()),
              firstDate: firstDate,
              lastDate: lastDate,
            );
            if (d != null) c.setDate(config.fieldKey, d);
          },
          borderRadius: BorderRadius.circular(10),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: _label(context),
              suffixIcon: const Icon(Icons.calendar_today, size: 20),
            ),
            child: Text(
              rxDate.value != null
                  ? DateFormat('dd MMM yyyy').format(rxDate.value!)
                  : _trLabel('Select date'),
              style: TextStyle(
                color: rxDate.value != null
                    ? AppTheme.textDark
                    : Colors.grey[400],
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileField(BuildContext context, FormController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c.textController(config.fieldKey),
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(10),
        ],
        decoration: InputDecoration(
          labelText: _label(context),
          prefixText: '+91  ',
        ),
        validator: (v) {
          if (v != null && v.isNotEmpty && v.length != 10) {
            return _trLabel('10 digits required');
          }
          if (config.isRequired && (v == null || v.isEmpty)) {
            return _trLabel('Required');
          }
          return null;
        },
      ),
    );
  }

  Widget _buildAadharField(BuildContext context, FormController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c.textController(config.fieldKey),
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d ]')),
          _AadharFormatter(),
        ],
        decoration: InputDecoration(
          labelText: _label(context),
          hintText:
              _localizedHint(context) ?? UiStrings.t('aadhaar_input_hint'),
        ),
        validator: (v) {
          if (v != null && v.isNotEmpty) {
            final digits = v.replaceAll(' ', '');
            if (digits.length != 12) return _trLabel('12 digits required');
          }
          if (config.isRequired && (v == null || v.isEmpty)) {
            return _trLabel('Required');
          }
          return null;
        },
      ),
    );
  }

  Widget _buildAutoCalcDisplay(BuildContext context, FormController c) {
    final rx = c.autoCalcValue(config.fieldKey);
    return Obx(
      () => Container(
        margin: const EdgeInsets.only(bottom: 14, top: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.greenPale,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.greenLight.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              UiStrings.fromEnglish(_label(context)),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.greenDark,
              ),
            ),
            Text(
              UiStrings.f('rs_value', {
                'value': LocaleText.number(rx.value, fractionDigits: 2),
              }),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? Function(String?)? _buildValidator() {
    return (String? v) {
      if (config.isRequired && (v == null || v.isEmpty)) {
        return _trLabel('Required');
      }
      if (v == null || v.isEmpty) return null;

      final rules = config.validation;
      if (rules.containsKey('min_length')) {
        final minLen = rules['min_length'] as int;
        if (v.length < minLen) {
          return UiStrings.f('minimum_characters', {'count': minLen});
        }
      }
      if (rules.containsKey('max_length')) {
        final maxLen = rules['max_length'] as int;
        if (v.length > maxLen) {
          return UiStrings.f('maximum_characters', {'count': maxLen});
        }
      }
      if (rules.containsKey('regex')) {
        final regex = RegExp(rules['regex'] as String);
        if (!regex.hasMatch(v)) {
          return UiStrings.fromEnglish(
            (rules['regex_message'] as String?) ??
                UiStrings.t('invalid_format'),
          );
        }
      }
      return null;
    };
  }
}

class _AadharFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(' ', '');
    if (digits.length > 12) return oldValue;
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
