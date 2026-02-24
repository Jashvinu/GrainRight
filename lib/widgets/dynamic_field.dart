import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../controllers/form_controller.dart';
import '../models/form_config.dart';
import 'acre_input.dart';
import 'custom_dropdown.dart';
import 'custom_text_field.dart';
import 'yes_no_toggle.dart';

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

  Widget _buildField(BuildContext context, FormController c) {
    return switch (config.inputType) {
      'text' => CustomTextField(
          label: _label,
          controller: c.textController(config.fieldKey),
          suffixText: config.suffixText,
          validator: _buildValidator(),
        ),
      'numeric' => CustomTextField(
          label: _label,
          controller: c.textController(config.fieldKey),
          numeric: true,
          suffixText: config.suffixText,
          validator: _buildValidator(),
        ),
      'currency' => _buildCurrencyField(c),
      'acre' => AcreInput(
          label: config.label,
          controller: c.textController(config.fieldKey),
        ),
      'boolean' => YesNoToggle(
          label: config.label,
          value: c.boolValue(config.fieldKey),
        ),
      'dropdown' => _buildDropdown(c),
      'date' => _buildDatePicker(context, c),
      'mobile' => _buildMobileField(c),
      'aadhar' => _buildAadharField(c),
      'auto_calc' => _buildAutoCalcDisplay(c),
      _ => const SizedBox.shrink(),
    };
  }

  String get _label =>
      config.isRequired ? '${config.label} *' : config.label;

  Widget _buildCurrencyField(FormController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c.textController(config.fieldKey),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
        ],
        decoration: InputDecoration(
          labelText: _label,
          prefixText: 'Rs  ',
          suffixText: config.suffixText,
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

  Widget _buildDropdown(FormController c) {
    final items = c.dropdownOptions[config.dropdownOptionsKey] ?? [];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: InputDecorator(
          decoration: InputDecoration(labelText: config.label),
          child: Text('No options', style: TextStyle(color: Colors.grey[400])),
        ),
      );
    }
    return CustomDropdown(
      label: config.label,
      items: items,
      selected: c.dropdownValue(config.fieldKey),
    );
  }

  Widget _buildDatePicker(BuildContext context, FormController c) {
    final rxDate = c.dateValue(config.fieldKey);
    DateTime firstDate = DateTime(2020);
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
      child: Obx(() => InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: rxDate.value ??
                    (lastDate.isBefore(DateTime.now()) ? lastDate : DateTime.now()),
                firstDate: firstDate,
                lastDate: lastDate,
              );
              if (d != null) rxDate.value = d;
            },
            borderRadius: BorderRadius.circular(10),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: config.label,
                suffixIcon: const Icon(Icons.calendar_today, size: 20),
              ),
              child: Text(
                rxDate.value != null
                    ? DateFormat('dd MMM yyyy').format(rxDate.value!)
                    : 'Select date',
                style: TextStyle(
                  color: rxDate.value != null ? AppTheme.textDark : Colors.grey[400],
                  fontSize: 14,
                ),
              ),
            ),
          )),
    );
  }

  Widget _buildMobileField(FormController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c.textController(config.fieldKey),
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(10),
        ],
        decoration: const InputDecoration(
          labelText: 'Mobile No.',
          prefixText: '+91  ',
        ),
        validator: (v) {
          if (v != null && v.isNotEmpty && v.length != 10) {
            return '10 digits required';
          }
          if (config.isRequired && (v == null || v.isEmpty)) return 'Required';
          return null;
        },
      ),
    );
  }

  Widget _buildAadharField(FormController c) {
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
          labelText: config.label,
          hintText: config.hintText ?? 'XXXX XXXX XXXX',
        ),
        validator: (v) {
          if (v != null && v.isNotEmpty) {
            final digits = v.replaceAll(' ', '');
            if (digits.length != 12) return '12 digits required';
          }
          if (config.isRequired && (v == null || v.isEmpty)) return 'Required';
          return null;
        },
      ),
    );
  }

  Widget _buildAutoCalcDisplay(FormController c) {
    final rx = c.autoCalcValue(config.fieldKey);
    return Obx(() => Container(
          margin: const EdgeInsets.only(bottom: 14, top: 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.greenPale,
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: AppTheme.greenLight.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                config.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.greenDark,
                ),
              ),
              Text(
                'Rs ${rx.value.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.green,
                ),
              ),
            ],
          ),
        ));
  }

  String? Function(String?)? _buildValidator() {
    return (String? v) {
      if (config.isRequired && (v == null || v.isEmpty)) return 'Required';
      if (v == null || v.isEmpty) return null;

      final rules = config.validation;
      if (rules.containsKey('min_length')) {
        final minLen = rules['min_length'] as int;
        if (v.length < minLen) return 'Minimum $minLen characters';
      }
      if (rules.containsKey('max_length')) {
        final maxLen = rules['max_length'] as int;
        if (v.length > maxLen) return 'Maximum $maxLen characters';
      }
      if (rules.containsKey('regex')) {
        final regex = RegExp(rules['regex'] as String);
        if (!regex.hasMatch(v)) {
          return (rules['regex_message'] as String?) ?? 'Invalid format';
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
